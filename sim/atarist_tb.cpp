/*
  atarist_tb.cpp

  MiSTeryNano verilator testbench
*/

#include <stdlib.h>
#include <iostream>
#include <fstream>
#include <iomanip>

#include <SDL.h>
#include <SDL_image.h>

#include "Vatarist_tb.h"
#include "verilated.h"
#include "verilated_fst_c.h"

#include "sd_card_config.h"

Vatarist_tb *tb;
static VerilatedFstC *trace;
double simulation_time;

#define TOS "etos192uk.img"

// optionally parse a sector address into track/side/sector
char *sector_string(int drive, uint32_t lba) {
  static char str[32];
  strcpy(str, "");
  return str;
}

#define RAMSIZE  512

// these numbers are for TOS1.04 on a 512kBytes warm boot (ram.img present)

// #define TRACESTART   0.0
// #define TRACESTART   0.2
// #define TRACESTART   1.59   // first sector is read from sd card into buffer
// #define TRACESTART   1.75   // first sector is read from buffer into dma
// #define TRACESTART   2.4    // floppy root dir read
// #define TRACESTART   2.5    // floppy desktop.inf read

#ifdef TRACESTART
#define TRACEEND     (TRACESTART + 0.1)   // run for 100ms
#endif

// image name use to write ram to disk
#define RAMFILE  "ram.img"  

/* =============================== video =================================== */

#define MAX_H_RES   (2048+100)  // a little more than 2048 to see how the Atari scales to 2048 in PAL
#define MAX_V_RES   1024

SDL_Window*   sdl_window   = NULL;
SDL_Renderer* sdl_renderer = NULL;
SDL_Texture*  sdl_texture  = NULL;
int sdl_cancelled = 0;

typedef struct Pixel {  // for SDL texture
    uint8_t a;  // transparency
    uint8_t b;  // blue
    uint8_t g;  // green
    uint8_t r;  // red
} Pixel;

#define SCALE 1
Pixel screenbuffer[MAX_H_RES*MAX_V_RES];

void init_video(void) {
  if (SDL_Init(SDL_INIT_VIDEO) < 0) {
    printf("SDL init failed.\n");
    return;
  }

  // start with a 512x313 or scandoubed 1024x626 screen
  sdl_window = SDL_CreateWindow("MiSTeryNano", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, SCALE*512, SCALE*313, SDL_WINDOW_RESIZABLE | SDL_WINDOW_SHOWN);
  if (!sdl_window) {
    printf("Window creation failed: %s\n", SDL_GetError());
    return;
  }
  
  sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
            SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
  if (!sdl_renderer) {
    printf("Renderer creation failed: %s\n", SDL_GetError());
    return;
  }
}

// https://stackoverflow.com/questions/34255820/save-sdl-texture-to-file
void save_texture(SDL_Renderer *ren, SDL_Texture *tex, const char *filename) {
    SDL_Texture *ren_tex = NULL;
    SDL_Surface *surf = NULL;
    int w, h;
    int format = SDL_PIXELFORMAT_RGBA32;;
    void *pixels = NULL;

    /* Get information about texture we want to save */
    int st = SDL_QueryTexture(tex, NULL, NULL, &w, &h);
    if (st != 0) { SDL_Log("Failed querying texture: %s\n", SDL_GetError()); goto cleanup; }

    // adjust aspect ratio
    while(w > 2*h) w/=2;
    
    ren_tex = SDL_CreateTexture(ren, format, SDL_TEXTUREACCESS_TARGET, w, h);
    if (!ren_tex) { SDL_Log("Failed creating render texture: %s\n", SDL_GetError()); goto cleanup; }

    /* Initialize our canvas, then copy texture to a target whose pixel data we can access */
    st = SDL_SetRenderTarget(ren, ren_tex);
    if (st != 0) { SDL_Log("Failed setting render target: %s\n", SDL_GetError()); goto cleanup; }

    SDL_SetRenderDrawColor(ren, 0x00, 0x00, 0x00, 0x00);
    SDL_RenderClear(ren);

    st = SDL_RenderCopy(ren, tex, NULL, NULL);
    if (st != 0) { SDL_Log("Failed copying texture data: %s\n", SDL_GetError()); goto cleanup; }

    /* Create buffer to hold texture data and load it */
    pixels = malloc(w * h * SDL_BYTESPERPIXEL(format));
    if (!pixels) { SDL_Log("Failed allocating memory\n"); goto cleanup; }

    st = SDL_RenderReadPixels(ren, NULL, format, pixels, w * SDL_BYTESPERPIXEL(format));
    if (st != 0) { SDL_Log("Failed reading pixel data: %s\n", SDL_GetError()); goto cleanup; }

    /* Copy pixel data over to surface */
    surf = SDL_CreateRGBSurfaceWithFormatFrom(pixels, w, h, SDL_BITSPERPIXEL(format), w * SDL_BYTESPERPIXEL(format), format);
    if (!surf) { SDL_Log("Failed creating new surface: %s\n", SDL_GetError()); goto cleanup; }

    /* Save result to an image */
    st = IMG_SavePNG(surf, filename);
    if (st != 0) { SDL_Log("Failed saving image: %s\n", SDL_GetError()); goto cleanup; }
    
    // SDL_Log("Saved texture as PNG to \"%s\" sized %dx%d\n", filename, w, h);

cleanup:
    SDL_FreeSurface(surf);
    free(pixels);
    SDL_DestroyTexture(ren_tex);
}

void capture_video(void) {
  static int last_hs_n = -1;
  static int last_vs_n = -1;
  static int sx = 0;
  static int sy = 0;
  static int frame = 0;
  static int frame_line_len = 0;
  
  // store pixel
  if(sx < MAX_H_RES && sy < MAX_V_RES) {  
    Pixel* p = &screenbuffer[sy*MAX_H_RES + sx];
    p->a = 0xFF;  // transparency
    p->b = tb->b<<2;
    p->g = tb->g<<2;
    p->r = tb->r<<2;
  }
  sx++;
    
  if(tb->hsync_n != last_hs_n) {
    last_hs_n = tb->hsync_n;

    // trigger on rising hs edge
    if(tb->hsync_n) {
      // no line in this frame detected, yet
      if(frame_line_len >= 0) {
	if(frame_line_len == 0)
	  frame_line_len = sx;
	else {
	  if(frame_line_len != sx) {
	    printf("frame line length changed from %d to %d\n", frame_line_len, sx);
	    frame_line_len = -1;	  
	  }
	}
      }
      
      sx = 0;
      sy++;
    }    
  }

  if(tb->vsync_n != last_vs_n) {
    last_vs_n = tb->vsync_n;

    // trigger on rising vs edge
    if(tb->vsync_n) {
      // draw frame if valid
      if(frame_line_len > 0) {
	
	// check if current texture matches the frame size
	if(sdl_texture) {
	  int w=-1, h=-1;
	  SDL_QueryTexture(sdl_texture, NULL, NULL, &w, &h);
	  if(w != frame_line_len || h != sy) {
	    SDL_DestroyTexture(sdl_texture);
	    sdl_texture = NULL;
	  }
	}
	  
	if(!sdl_texture) {
	  sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
					  SDL_TEXTUREACCESS_TARGET, frame_line_len, sy);
	  if (!sdl_texture) {
	    printf("Texture creation failed: %s\n", SDL_GetError());
	    sdl_cancelled = 1;
	  }
	}
	
	if(sdl_texture) {	
	  SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, MAX_H_RES*sizeof(Pixel));
	  
	  SDL_RenderClear(sdl_renderer);
	  SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL);
	  SDL_RenderPresent(sdl_renderer);

	  char name[32];
	  sprintf(name, "screenshots/frame%04d.png", frame);
	  save_texture(sdl_renderer, sdl_texture, name);
	}
      }
	
      // process SDL events
      SDL_Event event;
      while( SDL_PollEvent( &event ) ){
	if(event.type == SDL_QUIT)
	  sdl_cancelled = 1;
	
	if(event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE)
	    sdl_cancelled = 1;
      }
      
      printf("%.3fms frame %d is %dx%d\n", simulation_time*1000, frame, frame_line_len, sy);

      frame++;
      frame_line_len = 0;
      sy = 0;
    }    
  }
}

static uint64_t GetTickCountMs() {
  struct timespec ts;
  
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)(ts.tv_nsec / 1000000) + ((uint64_t)ts.tv_sec * 1000ull);
}

#define RAMMASK ((RAMSIZE*1024)-1)
static unsigned char ram[RAMSIZE*1024];
static unsigned char rom[256*1024];

void check_ram(int addr) {
  // check for system variables to be written
  // http://tho-otto.de/hypview/hypview.cgi?url=%2Fhyp%2Fpasm.hyp&charset=UTF-8&index=362
  static struct { int addr; const char *name; int cur; } sysvars[] = {
    { 0x420, "MEMVALID" }, { 0x42e, "PHYSTOP " },
    { 0x432, "MEMBOT  " }, { 0x436, "MEMTOP  " },
    { 0x43a, "MEMVAL2 " }, { 0x51a, "MEMVAL3 " },

    // system counters
    //{ 0x462, "VBCLOCK " }, { 0x4ba, "HZ_200  " },
    
    { 0, NULL }
  };
  
  for(int i=0;sysvars[i].addr;i++) {
    if((addr == sysvars[i].addr) || (addr == sysvars[i].addr+2) || (addr == -1)) {
      int v = 256*256*256*ram[sysvars[i].addr] + 256*256*ram[sysvars[i].addr+1] +
	256*ram[sysvars[i].addr+2] + ram[sysvars[i].addr+3];
      
      if(v != sysvars[i].cur) {	    
	printf("%.3fms %s changed to $%08x\n", simulation_time*1000, sysvars[i].name, v);
	sysvars[i].cur = v;
      }
    }
  }  
}

void init_mem() {
  FILE *file=fopen(TOS, "rb");
  if(!file) { perror("loading tos"); exit(-1); }
  int len = fread(rom, 1024, 256, file);
  printf("Loaded %d kBytes rom image\n", len);
  fclose(file);

  // load ram if present  
  file=fopen(RAMFILE, "rb");
  if(!file)
    perror("loading ram");
  else {
    int len = fread(ram, 1024, RAMSIZE, file);
    fclose(file);

    printf("Loaded %d kBytes ram image\n", len);

    check_ram(-1);
  }
}

void tick(int c) {
  static int old_addr = 0xffffff;
  static uint64_t ticks = 0;
  
  tb->clk_32 = c; 
  tb->eval();

  if(simulation_time == 0)
    ticks = GetTickCountMs();
  
  // after one simulated millisecond calculate real time */
  if(simulation_time >= 0.001 && ticks) {
    ticks = GetTickCountMs() - ticks;
    printf("Speed factor = %lu\n", ticks);
    ticks = 0;
  }
  
  // trace after
#ifdef TRACESTART
  if(simulation_time > TRACESTART) trace->dump(1000000000000 * simulation_time);
#endif
  // each tick is 1/64 us or 15,625ns as we are simulating a 32 MHz clock
  simulation_time += TICKLEN;

  if (c && !tb->rom_n) {
    // rom access
    tb->rom_data_out = (rom[(tb->rom_addr<<1) & 0x3ffff] * 256) + rom[((tb->rom_addr<<1) + 1)& 0x3ffff];
  }
  
  // max 4 MB RAM
  if (c && !tb->ram_ras_n && !tb->ram_ref && tb->ram_addr < 0x200000) {
    if((!tb->ram_cash_n || !tb->ram_casl_n) && !((tb->ram_addr<<1) & ~RAMMASK) ){      
      if(tb->ram_we_n) {	
	tb->ram_data_out = (ram[(tb->ram_addr<<1)] * 256) + ram[(tb->ram_addr<<1) + 1];
      } else {
	// we expect to see ram writes always in cycle 2 as video never writes
	if(!tb->ram_cash_n) ram[(tb->ram_addr<<1)]     = (tb->ram_data_in & 0xff00) >> 8;	
	if(!tb->ram_casl_n) ram[(tb->ram_addr<<1) + 1] =  tb->ram_data_in & 0xff;

	check_ram((tb->ram_addr<<1));
      }
    }
  }
  
  if(c) {
    // full sd card emulation enabled
    sd_handle();
    
    capture_video();
  }
}

int main(int argc, char **argv) {
  init_mem();  
  
  // Initialize Verilators variables
  Verilated::commandArgs(argc, argv);
  // Verilated::debug(1);
  Verilated::traceEverOn(true);
  trace = new VerilatedFstC;
  trace->spTrace()->set_time_unit("1ns");
  trace->spTrace()->set_time_resolution("1ps");
  simulation_time = 0;

  init_video();
    
  // Create an instance of our module under test
  tb = new Vatarist_tb;
  tb->trace(trace, 99);
  trace->open("atarist_tb.fst");

  sd_init();
  
  tb->mono_detect = 1;  // color=1, mono=0
  
  // apply reset and power-on for a while */
  tb->resb = 0; tb->porb = 0;
  for(int i=0;i<100;i++) { tick(1); tick(0); }
  tb->porb = 1;
  for(int i=0;i<100;i++) { tick(1); tick(0); }
  tb->resb = 1;
  
  /* run for a while */
  while(!sdl_cancelled
#ifdef TRACESTART
	&& simulation_time<TRACEEND
#endif
	) {
    tick(1);
    tick(0);
    
  }
  
  printf("stopped after %.3fms\n", 1000*simulation_time);

  // write ram to disk to e.g. warmboot on next run
  printf("Writing " RAMFILE "...\n");
  FILE *f = fopen(RAMFILE, "wb");
  if(!f)
    perror("fopen(" RAMFILE ")");
  else {
    fwrite(ram, 1024, RAMSIZE, f);
    fclose(f);    
  }
  
  trace->close();
}
