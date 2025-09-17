import struct, random

from bootloader import BOOTLOADER

# parse hexdump and create a 512 byte sector from it
def hex2sector(hexdump):
    sector = bytearray(512)

    i = 0
    for line in hexdump.splitlines():
        # remove everythig before first space and after first |
        line = line.split(" ",1)
        if len(line) > 1:
            line = line[1].split("|", 1)[0].split()
            if len(line) != 16:
                print("Internal hex parsing failed")
                return None
            
            for num in line:
                sector[i] = int(num, 16)
                i = i + 1
        
    return sector

def adjust_csum(sec, csum=0x1234):
    # adjust sector checksum
    for i in range(255): csum = (csum - struct.unpack(">H", sec[2*i:2*i+2])[0]) & 0xffff
    sec[510:512] = struct.pack(">H", csum)

def file_exists(fs, name):
    # search for a file in root dir only
    
    for d in fs:
        if d["name"] == name:
            return d

    return None
    
def write_mbr(f, partitions, options, driver=None):
    print("Writing MBR")

    # extra sectors between MBR and first partition. Typically 1
    EXTRA = 1

    # write MBR and empty sectors incl. bootloader
    if driver:
        print("Including", driver["name"], "MBR bootloader")
        mbr = hex2sector(driver["mbr"])
        if not mbr: return False
    else:
        mbr = bytearray(512)

    # calculate required image size
    begin = EXTRA+1              # mbr + 1 unused sector
    total = begin
    for p in partitions:
        total += p["size"]

    # write total media size
    mbr[0x1c2:0x1c6] = struct.pack(">L", total)

    # write partition entries
    for i in range(len(partitions)):
        # TODO: check if data actually fits into a regular 'GEM' partition
        # set bootable flag if bootloader is to be included
        mbr[0x1c6+12*i:0x1c6+12*(i+1)] = struct.pack(">B3sLL", 0x81 if i == 0 and driver else 0x01, b"GEM", begin, partitions[i]["size"])
        begin += partitions[i]["size"]

    if driver:
        adjust_csum(mbr)

    # write the mbr ...
    f.write(mbr)

    # .. and the extra sectors
    for i in range(EXTRA):
        f.write(bytearray(512))

    return True
    
def import_fs(fs, fat, data):

    def import_dir(d, parent, fat, data):
        def fat_allocate(fat, size):
            chain = []
            
            # a cluster is always two sectors which in turn is always 1024 bytes                
            clusters = (size+1023)//1024
            if not clusters: clusters = 1   # empty file uses one cluster
            
            # search FAT for entries
            # start search at FAT index 2
            start = 2
            while fat[start]: start += 1

            cur = start
            while clusters:
                chain.append(cur)
                
                # will we need a next cluster?
                if clusters > 1:                    
                    next = cur+1
                    while fat[next]: next += 1
                    # TODO: check if we reached end of fat (image is full)
                else:
                    # end of cluster chain marker
                    next = 0xffff

                fat[cur] = next
                cur = next
                clusters = clusters - 1

            return chain
        
        entries = []
        for f in d:
            # create a directory entry for this
            entry = bytearray(32)

            # write 8+3 file name
            entry[0:11] = b"           "
            name = f["name"].split(".")[0].encode("latin-1")
            entry[0:len(name)] = name
            if "." in f["name"]:
                ext = f["name"].split(".",1)[1].encode("latin-1")
                entry[8:8+len(ext)] = ext

            # write date and time
            entry[22:26] = struct.pack("<HH", f["time"], f["date"])
            
            if "subdir" in f:
                # allocate enough space for all subdirectory entries
                clusters = fat_allocate(fat, 32*(len(f["subdir"])+2))
                
                entry[11] = 0x10

                # create '.' and '..' entries
                dot_entry = bytearray(32)
                dot_entry[0:11] = b".          "  # name
                dot_entry[11] = 0x10              # attr
                dot_entry[22:26] = struct.pack("<HH", f["time"], f["date"])
                dot_entry[26:28] = struct.pack("<H", clusters[0])

                dotdot_entry = bytearray(32)
                dotdot_entry[0:11] = b"..         "  # name
                dotdot_entry[11] = 0x10              # attr
                dotdot_entry[22:26] = struct.pack("<HH", f["time"], f["date"])
                dotdot_entry[26:28] = struct.pack("<H", parent)

                subdir = [ dot_entry, dotdot_entry ]
                subdir.extend(import_dir(f["subdir"], clusters[0], fat, data))

                # write directory entries into clusters allocated by fat_allocate
                cluster = 0
                while subdir:
                    # we can write 16 entries per sector and two sectors per cluster
                    sector = 0
                    while subdir and sector < 2: 
                    
                        index = 0
                        while subdir and index < 16: 
                            data[2*(clusters[cluster]-2)+sector][32*index:32*(index+1)] = subdir[0]

                            subdir = subdir[1:]                                  
                            index += 1
                        sector += 1
                    cluster += 1
                            
                # save start cluster in entry
                entry[26:28] = struct.pack("<H", clusters[0]) 
            else:
                # import a regular file
                # print("import", f["name"], "len", f["size"])
                
                # no need to write attribute byte as it's set to zero by default
                # write file length
                entry[28:32] = struct.pack("<L", len(f["data"]))                

                clusters = fat_allocate(fat, len(f["data"]))

                offset = 0
                for c in clusters:
                    # write data to both sectors of a cluster
                    for s in range(2):
                        bytes2copy = 512 if len(f["data"])-offset > 512 else len(f["data"])-offset
                        if bytes2copy:
                            data[2*(c-2)+s][0:bytes2copy] = f["data"][offset:offset+bytes2copy]
                            
                        offset += bytes2copy
                
                # save start cluster in entry
                entry[26:28] = struct.pack("<H", clusters[0]) 

            if len(entry) != 32:
                # this is actually an internal error and should never happen
                print("Error, directory length mismatch", len(entry))
                return None
                
            entries.append(entry)                

        return entries
            
    return import_dir(fs, 0, fat, data)
    
def write_partition(f, part, options, drive, driver):
    print("Creating Partition", ["C:","D:","E:","F:"][drive])

    # ========================== create boot sector ==================================
    if drive == 0 and driver:
        print("Including", driver["name"], "bootsector")
        bootsector = hex2sector(driver["bootsector"])
        if not bootsector: return False
    else:
        bootsector = bytearray(512)

    # TODO: calculate a sane number of root directory entries
    ndirs = 416

    # calculate number of fat sectors needed
    nsects = part["size"]
    spf = ((nsects - 1 - ndirs//16)+511) // 512  # 256 clusters of two sectors per cluster per sector

    # the serial number should be random to detect media changes
    random_serial = bytearray([random.randint(0,255) for i in range(3)])
    
    # setup bootsector values
    bootsector[2:16] = struct.pack("<6s3sHBH", bytearray([0,0,0,0,0,0]), random_serial, 512, 2, 1)
    bootsector[16:30] = struct.pack("<BHHBHHHH", 2, ndirs, nsects, 0xf8, spf, 0,0,0) 

    # adjust checksum to make bootsector bootable
    if drive == 0 and driver: adjust_csum(bootsector)    

    f.write(bootsector)

    # ========================== create data area ==================================
    data = [bytearray(512) for x in range(nsects-2*spf-ndirs//16-1)]
    
    # ========================== setup empty FAT ==================================
    fat = [0 for x in range(spf*256)]   # 256 FAT16 entries per sector    
    fat[0] = 0xfff8
    fat[1] = 0xffff
    
    # ========================== populate file system ==================================
    rootdir = import_fs(part["files"], fat, data)

    # write FAT twice
    print("Writing FATs ...")    
    for j in range(2):
        for i in range(spf):
            sec = bytearray(512)
            for e in range(256): sec[2*e:2*e+2] = struct.pack("<H", fat[256*i+e])
            f.write(sec)
        
    # write root directory
    print("Writing root directory ...")    
    if len(rootdir) > ndirs:
        print("Error, root directory overflow")
        return False

    for s in range(ndirs//16):
        sec = bytearray(512)

        # write root dir entries into sector
        e = 0
        while len(rootdir) and e < 16:
            sec[e*32:(e+1)*32] = rootdir[0]
            rootdir = rootdir[1:]
            e += 1
        
        # this is an internal error and indicates that this script is broken ...
        if len(sec) != 512: print("Error, invalid directory sector length", len(sec))        
        f.write(sec)
    
    # write data area
    print("Writing data ...")    
    for sector in data:
        # this is an internal error and indicates that this script is broken ...
        if len(sector) != 512: print("Error, invalid data sector length", len(sector))        
        f.write(sector)

    return True
    
def write_hddimage(name, partitions, options):
    print("== writing '"+name+"' ==")

    try:
        f = open(name, "wb")
    except Exception as e:
        print("Exception:", str(e))
        return False

    # check if filesytem contains a known harddisk driver
    driver = None
    for d in BOOTLOADER:
        if len(partitions):
            bloader = file_exists(partitions[0]["files"], d["file"])
            if bloader:
                print("Partition C: contains", d["name"], d["file"])
            
                # check if we are supposed to patch the boot loader
                if "patch" in d:
                    print("Applying bootloader patches:", d["patchdesc"])
                    data = list(bloader["data"])
                    for patch in d["patch"]:
                        if data:
                            if data[patch[0]] == patch[1]:
                                data[patch[0]] = patch[2]
                            else:
                                print("Patch failed")
                                data = None
                    
                if data:
                    bloader["data"] = data
                    
                driver = d
    
    write_mbr(f, partitions, options, driver)

    for p in range(len(partitions)):
        write_partition(f, partitions[p], options, p, driver)
    
    f.close()

    return True
