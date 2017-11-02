module gbcgpu;

pragma(msg, "TODO: import useless");
import std.stdio;
import std.string;
import std.algorithm;
import std.conv;
import std.range;

import interfaces.gpu;
import interfaces.cpu;
import interfaces.mmu8b;
import interfaces.renderer;


final class GbcGpu : Mmu8bItf
{
    pragma(msg, "TODO: LCD status byte not currently used");
    pragma(msg, "TODO: LCD status byte initial value is not defined");


    private:

    version(gpu_tracing)
        static immutable bool tracing = true;
    else
        static immutable bool tracing = false;

    immutable bool useCgb;
    ubyte[0x4000] videoRam = 0x00; // 16 Ko (note: 8Ko for pre-GBC console)
    ubyte[0xA0] spriteAttributeTable = 0x00; // 160 octets (40 entries x 4 octets)
    RendererItf renderer;
    CpuItf cpu;
    uint internalClock = 0;
    ubyte lcdControl = 0x91;
    ubyte curLine = 0;
    ubyte lyc = 0;
    ubyte lcdStatus = 0x83;
    ubyte tileMode = 0x00;
    ubyte scrollX = 0x00;
    ubyte scrollY = 0x00;
    ubyte windowX = 0x00;
    ubyte windowY = 0x00;
    ubyte ramBank = 0x00;
    ubyte sgbBgPaletteData = 0xFC;
    ubyte[2] sgbSpritePaletteData = [0xFF, 0xFF];
    ubyte cgbBgPaletteId = 0x00; // Not defined
    ubyte[0x40] cgbBgPaletteData = 0xFF; // 64 octets ([...] x 2 octets per color)
    ubyte cgbSpritePaletteId = 0x00; // Not defined
    ubyte[0x40] cgbSpritePaletteData = 0xFF; // 64 octets (8 entries x 4 colors x 2 octets per color)
    uint[160] tmpRawLine;
    static immutable ubyte[] sgbPalette = [0xFF, 0xAA, 0x55, 0x00];
    bool[160] bgPriority;


    public:

    this(bool cgbMode)
    {
        useCgb = cgbMode;
    }

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x80: .. case 0x9F:
                return videoRam[(ramBank << 13) | (address - 0x8000)];

            case 0xFE: .. case 0xFF:
                switch(address)
                {
                    case 0xFE00: .. case 0xFE9F:
                        return spriteAttributeTable[address - 0xFE00];

                    case 0xFF40:
                        return lcdControl;

                    case 0xFF41:
                        return lcdStatus;

                    case 0xFF42:
                        return scrollY;

                    case 0xFF43:
                        return scrollX;

                    case 0xFF44:
                        return curLine;

                    case 0xFF45:
                        return lyc;

                    case 0xFF47:
                        return sgbBgPaletteData;

                    case 0xFF48:
                        return sgbSpritePaletteData[0];

                    case 0xFF49:
                        return sgbSpritePaletteData[1];

                    case 0xFF4A:
                        return windowY;

                    case 0xFF4B:
                        return windowX;

                    case 0xFF4F:
                        return ramBank | 0b11111110;

                    case 0xFF68:
                        return cgbBgPaletteId;

                    case 0xFF69:
                        return cgbBgPaletteData[cgbBgPaletteId & 0x3F];

                    case 0xFF6A:
                        return cgbSpritePaletteId;

                    case 0xFF6B:
                        return cgbSpritePaletteData[cgbBgPaletteId & 0x3F];

                    default:
                        throw new Exception(format("Execution failure: IO Ports access not implemented (port: 0x%0.2X, mode:read)", address-0xFF00));
                        //throw new Exception("Execution failure: Out of memory access (read)");
                }

            default:
                throw new Exception("Execution failure: Out of memory access (read)");
        }
    }

    void saveByte(ushort address, ubyte value)
    {
        switch(address >> 8)
        {
            case 0x80: .. case 0x9F:
                videoRam[(ramBank << 13) | (address - 0x8000)] = value;
                break;

            case 0xFE: .. case 0xFF:
                switch(address)
                {
                    case 0xFE00: .. case 0xFE9F:
                        spriteAttributeTable[address - 0xFE00] = value;
                        break;

                    case 0xFF40:
                        lcdControl = value;
                        break;

                    case 0xFF41:
                        lcdStatus = (value & 0b01111000) | (lcdStatus & 0b10000111);
                        pragma(msg, "TODO: See whether setting the LCD status register reset the line counter (internalClock=0 cause bug on the zilog demo)");
                        break;

                    case 0xFF42:
                        scrollY = value;
                        break;

                    case 0xFF43:
                        scrollX = value;
                        break;

                    case 0xFF45:
                        lyc = value;
                        break;

                    case 0xFF47:
                        sgbBgPaletteData = value;
                        break;

                    case 0xFF48:
                        sgbSpritePaletteData[0] = value;
                        break;

                    case 0xFF49:
                        sgbSpritePaletteData[1] = value;
                        break;

                    case 0xFF4A:
                        windowY = value;
                        break;

                    case 0xFF4B:
                        windowX = value;
                        break;

                    case 0xFF4F:
                        if(useCgb)
                            ramBank = value & 0b00000001;
                        else
                            writefln("WARNING: writting on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                        break;

                    case 0xFF68:
                        cgbBgPaletteId = value;
                        break;

                    case 0xFF69:
                        const ubyte id = cgbBgPaletteId & 0x3F;
                        cgbBgPaletteData[id] = value;
                        if((cgbBgPaletteId & 0x80) != 0)
                            cgbBgPaletteId = (cgbBgPaletteId & 0x80) | ((id + 1) & 0x3F);
                        break;

                    case 0xFF6A:
                        pragma(msg, "TODO: check STAT register (mode 3) to know whether the write has to be done");
                        cgbSpritePaletteId = value;
                        break;

                    case 0xFF6B:
                        const ubyte id = cgbSpritePaletteId & 0x3F;
                        cgbSpritePaletteData[id] = value;
                        if((cgbSpritePaletteId & 0x80) != 0)
                            cgbSpritePaletteId = (cgbSpritePaletteId & 0x80) | ((id + 1) & 0x3F);
                        break;

                    default:
                        throw new Exception(format("Execution failure: IO Ports access not implemented (port:0x%0.2X, mode:write)", address-0xFF00));
                        //throw new Exception("Execution failure: Out of memory access (read)");
                }
                break;

            default:
                throw new Exception("Execution failure: Out of memory access (read)");
        }
    }

    void connectRenderer(RendererItf renderer)
    {
        this.renderer = renderer;
    }

    void tick()
    {
        internalClock++;

        final switch(lcdMode())
        {
            case 0x00:
                if(internalClock >= 204)
                {
                    internalClock = 0;
                    curLine++;

                    if(curLine == 144)
                    {
                        lcdModeSetting(1);

                        if(lcdVblankIntFlag)
                            statInt();

                        vSyncInt();
                        renderer.swapBuffers();
                        pragma(msg, "TODO: vsync here ? (yes, but check before on Zelda with double speed mode)");
                    }
                    else
                        lcdModeSetting(2);
                }
                break;

            case 0x01:
                if(internalClock >= 456)
                {
                    internalClock = 0;
                    curLine++;

                    if(curLine >= 154)
                    {
                        lcdModeSetting(2);

                        if(lcdOamIntFlag)
                            statInt();

                        curLine = 0;
                        //vSyncInt();
                        pragma(msg, "TODO: vsync here ? (no)");
                    }
                }
                break;

            case 0x02:
                if(internalClock >= 80)
                {
                    internalClock = 0;
                    lcdModeSetting(3);

                    lcdCoincidenceFlagSetting(curLine == lyc);

                    if(curLine == lyc && lcdCoincidenceIntFlag)
                        statInt();
                }
                break;

            case 0x03:
                if(internalClock >= 172)
                {
                    internalClock = 0;
                    lcdModeSetting(0);

                    if(lcdHblankIntFlag)
                        statInt();

                    if(curLine < 144)
                    {
                        if(lcdOnFlag)
                        {
                            if(useCgb)
                                bgPriority[] = false;

                            if(bgOnFlag || useCgb)
                                renderBgScanline(curLine);

                            if(windowOnFlag)
                                renderWindowScanline(curLine);

                            if(spriteOnFlag)
                                renderSpriteScanline(curLine);
                        }
                    }
                }
                break;
        }
    }

    void connectCpu(CpuItf cpu)
    {
        this.cpu = cpu;
    }


    private:

    Color sgbBgColor(uint tilePixel) const
    {
        const ubyte gray = sgbPalette[(sgbBgPaletteData >> (tilePixel*2)) & 0x03];
        //const ubyte gray = cast(ubyte)(0x55 * (3 - ((sgbBgPaletteData >> (tilePixel*2)) & 0x03)));
        return Color(gray, gray, gray);
    }

    Color cgbBgColor(uint paletteId, uint tilePixel) const
    {
        const uint paletteOffset = paletteId*8 + tilePixel*2;
        const ubyte colorByte1 = cgbBgPaletteData[paletteOffset+0];
        const ubyte colorByte2 = cgbBgPaletteData[paletteOffset+1];
        const ubyte red = (colorByte1 & 0b00011111) << 3;
        const ubyte green = ((colorByte2 & 0b00000011) << 6) | ((colorByte1 & 0b11100000) >> 2);
        const ubyte blue = (colorByte2 & 0b01111100) << 1;
        return Color(red, green, blue);
    }

    Color sgbSpriteColor(uint paletteId, uint tilePixel) const
    {
        const ubyte gray = sgbPalette[(sgbSpritePaletteData[paletteId] >> (tilePixel*2)) & 0x03];
        return Color(gray, gray, gray);
    }

    Color cgbSpriteColor(uint paletteId, uint tilePixel) const
    {
        const uint paletteOffset = paletteId*8 + tilePixel*2;
        const ubyte colorByte1 = cgbSpritePaletteData[paletteOffset+0];
        const ubyte colorByte2 = cgbSpritePaletteData[paletteOffset+1];
        const ubyte red = (colorByte1 & 0b00011111) << 3;
        const ubyte green = ((colorByte2 & 0b00000011) << 6) | ((colorByte1 & 0b11100000) >> 2);
        const ubyte blue = (colorByte2 & 0b01111100) << 1;
        return Color(red, green, blue);
    }

    // Not synchronized with the LCD screen
    void renderBgScanline(uint y)
    {
        const uint tileMapOffset = (bgMapBaseFlag == 0) ? 0x1800 : 0x1C00;
        const(ubyte)[] tileMap = videoRam[tileMapOffset..tileMapOffset+0x0400];
        const(ubyte)[] cgbTileMap = videoRam[0x2000+tileMapOffset..0x2000+tileMapOffset+0x0400];

        const uint tileSetOffset = (bgAndWindowTileBaseFlag == 0) ? 0x0800 : 0x0000;
        const(ubyte)[] tileSet = videoRam[tileSetOffset..tileSetOffset+0x1000];
        const(ubyte)[] cgbTileSet = videoRam[0x2000+tileSetOffset..0x2000+tileSetOffset+0x1000];

        const ubyte tileIdMask = (bgAndWindowTileBaseFlag == 0) ? 0x80 : 0x00;

        const uint yMap = ((y + scrollY) % 256) / 8;
        const uint yTile = (y + scrollY) % 8;
        Color[160] scanLine;

        foreach(uint xBlock ; scrollX/8..scrollX/8+21)
        {
            const uint xMap = xBlock % 32;
            const ubyte tileId = tileMap[yMap * 32 + xMap] ^ tileIdMask;

            if(useCgb)
            {
                const ubyte cgbTileAttr = cgbTileMap[yMap * 32 + xMap];
                const uint cgbPaletteId = cgbTileAttr & 0b00000111;
                const uint cgbTileBank = (cgbTileAttr & 0b00001000) >> 3;
                const bool xFlip = (cgbTileAttr & 0b00100000) != 0;
                const bool yFlip = (cgbTileAttr & 0b01000000) != 0;
                const bool isFront = (cgbTileAttr & 0b10000000) != 0;
                pragma(msg, "TODO: isFront not fully tested");

                const(ubyte)[] tile = (cgbTileBank == 0) ? tileSet[tileId*16..tileId*16+16] : cgbTileSet[tileId*16..tileId*16+16];
                const uint yTileFinal = (yFlip) ? 7-yTile : yTile;
                const(ubyte)[] tileLine = tile[yTileFinal*2..yTileFinal*2+2];

                foreach(uint xTile ; 0..8)
                {
                    const int x = xBlock * 8 - scrollX + xTile;

                    if(x >= 0 && x < 160)
                    {
                        const uint xTileFinal = (xFlip) ? 7-xTile : xTile;
                        const uint bitPos = 7 - xTileFinal;
                        const uint mask = 1 << bitPos;
                        const uint pixel = ((tileLine[0] & mask) | ((tileLine[1] & mask) << 1)) >> bitPos;
                        const Color color = cgbBgColor(cgbPaletteId, pixel);

                        tmpRawLine[x] = pixel;
                        static if(tracing)
                            scanLine[x] = Color(color.r/4+191, (yFlip) ? color.g/4+127 : color.g/4+63, (xFlip) ? color.b/4+127 : color.b/4+31);
                        else
                            scanLine[x] = color;

                        bgPriority[x] = isFront;
                        //renderer.setPixel(x, y, color);
                    }
                }
            }
            else
            {
                const(ubyte)[] tile = tileSet[tileId*16..tileId*16+16];
                const(ubyte)[] tileLine = tile[yTile*2..yTile*2+2];

                foreach(uint xTile ; 0..8)
                {
                    const int x = xBlock * 8 - scrollX + xTile;

                    if(x >= 0 && x < 160)
                    {
                        const uint bitPos = 7 - xTile;
                        const uint mask = 1 << bitPos;
                        const uint pixel = ((tileLine[0] & mask) | ((tileLine[1] & mask) << 1)) >> bitPos;
                        const Color color = sgbBgColor(pixel);

                        tmpRawLine[x] = pixel;
                        static if(tracing)
                            scanLine[x] = Color(color.r/4+191, color.g/4+63, color.b/4+31);
                        else
                            scanLine[x] = color;
                        //renderer.setPixel(x, y, color);
                    }
                }
            }
        }

        renderer.setScanLine(y, scanLine);
    }

    // Not synchronized with the LCD screen
    void renderWindowScanline(uint y)
    {
        if(windowY <= y && windowX-7 < 160)
        {
            const uint tileMapOffset = (windowMapBaseFlag == 0) ? 0x1800 : 0x1C00;
            const(ubyte)[] tileMap = videoRam[tileMapOffset..tileMapOffset+0x0400];
            const(ubyte)[] cgbTileMap = videoRam[0x2000+tileMapOffset..0x2000+tileMapOffset+0x400];

            const uint tileSetOffset = (bgAndWindowTileBaseFlag == 0) ? 0x0800 : 0x0000;
            const(ubyte)[] tileSet = videoRam[tileSetOffset..tileSetOffset+0x1000];
            const(ubyte)[] cgbTileSet = videoRam[0x2000+tileSetOffset..0x2000+tileSetOffset+0x1000];

            const ubyte tileIdMask = (bgAndWindowTileBaseFlag == 0) ? 0x80 : 0x00;

            const uint yMap = (y - windowY) / 8;
            const uint yTile = (y - windowY) % 8;
            Color[160] scanLine;

            foreach(uint xMap ; 0..(160-(windowX-7)+7)/8)
            {
                const ubyte tileId = tileMap[yMap * 32 + xMap] ^ tileIdMask;

                if(useCgb)
                {
                    const ubyte cgbTileAttr = cgbTileMap[yMap * 32 + xMap];
                    const uint cgbPaletteId = cgbTileAttr & 0b00000111;
                    const uint cgbTileBank = (cgbTileAttr & 0b00001000) >> 3;
                    const bool xFlip = (cgbTileAttr & 0b00100000) != 0;
                    const bool yFlip = (cgbTileAttr & 0b01000000) != 0;
                    const bool isFront = (cgbTileAttr & 0b10000000) != 0;
                    pragma(msg, "TODO: isFront not fully tested");

                    const(ubyte)[] tile = (cgbTileBank == 0) ? tileSet[tileId*16..tileId*16+16] : cgbTileSet[tileId*16..tileId*16+16];
                    const uint yTileFinal = (yFlip) ? 7-yTile : yTile;
                    const(ubyte)[] tileLine = tile[yTileFinal*2..yTileFinal*2+2];

                    foreach(uint xTile ; 0..8)
                    {
                        const int x = xMap * 8 + (windowX-7) + xTile;

                        if(x >= 0 && x < 160)
                        {
                            const uint xTileFinal = (xFlip) ? 7-xTile : xTile;
                            const uint bitPos = 7 - xTileFinal;
                            const uint mask = 1 << bitPos;
                            const uint pixel = ((tileLine[0] & mask) | ((tileLine[1] & mask) << 1)) >> bitPos;
                            const Color color = cgbBgColor(cgbPaletteId, pixel);

                            bgPriority[x] |= isFront;

                            tmpRawLine[x] = pixel;
                            static if(tracing)
                                scanLine[x] = Color(color.r/4+63, color.g/4+191, color.b/4+31);
                            else
                                scanLine[x] = color;
                        }
                    }
                }
                else
                {
                    const(ubyte)[] tile = tileSet[tileId*16..tileId*16+16];
                    const(ubyte)[] tileLine = tile[yTile*2..yTile*2+2];

                    foreach(uint xTile ; 0..8)
                    {
                        const int x = xMap * 8 + (windowX-7) + xTile;

                        if(x >= 0 && x < 160)
                        {
                            const uint bitPos = 7 - xTile;
                            const uint mask = 1 << bitPos;
                            const uint pixel = ((tileLine[0] & mask) | ((tileLine[1] & mask) << 1)) >> bitPos;
                            const Color color = sgbBgColor(pixel);

                            tmpRawLine[x] = pixel;
                            static if(tracing)
                                scanLine[x] = Color(color.r/4+63, color.g/4+191, color.b/4+31);
                            else
                                scanLine[x] = color;
                        }
                    }
                }
            }

            if(windowX-7 <= 0)
                renderer.setScanLine(y, scanLine);
            else
                foreach(uint x ; windowX-7..160)
                    renderer.setPixel(x, y, scanLine[x]);
        }
    }

    // Not synchronized with the LCD screen
    void renderSpriteScanline(uint y)
    {
        const uint tileIdMask = largeSpriteOnFlag ? 0xFE : 0xFF;
        const(int)[] spriteIds;

        if(useCgb)
            spriteIds = iota(40).array;
        else
            spriteIds = iota(40).array.sort!((a, b) => spriteAttributeTable[a*4+1] < spriteAttributeTable[b*4+1]).array;

        foreach_reverse(int i ; spriteIds)
        {
            const uint yPos = spriteAttributeTable[i*4];
            const uint xPos = spriteAttributeTable[i*4 + 1];
            const uint tileIdBase = spriteAttributeTable[i*4 + 2];
            const uint attr = spriteAttributeTable[i*4 + 3];
            const uint cgbPaletteId = attr & 0b00000111;
            const uint cgbTileBank = (attr & 0b00001000) >> 3;
            const uint sgbPaletteId = (attr & 0b00010000) >> 4;
            const bool xFlip = (attr & 0b00100000) != 0;
            const bool yFlip = (attr & 0b01000000) != 0;
            const bool isBehind = (attr & 0b10000000) != 0;

            if(yPos <= y+16 && yPos > y+8 || largeSpriteOnFlag && yPos <= y+8 && yPos > y)
            {
                const uint tilePos = (yPos <= y+8) ? 1 : 0;
                const uint tileIdOffset = (largeSpriteOnFlag && yFlip) ? 1 - tilePos : tilePos;
                const uint tileId = (tileIdBase & tileIdMask) | tileIdOffset;
                const(ubyte)[] tileSet;

                if(useCgb)
                    tileSet = videoRam[0x2000*cgbTileBank..0x2000*cgbTileBank+0x1000];
                else
                    tileSet = videoRam[0x0000..0x1000];
                const(ubyte)[] tile = tileSet[tileId*16..tileId*16+16];

                uint yTile = y + 16 - yPos - tilePos*8;

                if(yFlip)
                    yTile = 7 - yTile;

                const(ubyte)[] tileLine = tile[yTile*2..yTile*2+2];

                foreach(uint xTile ; 0..8)
                {
                    const uint bitPos = 7 - xTile;
                    const uint mask = 1 << bitPos;
                    const uint pixel = ((tileLine[0] & mask) | ((tileLine[1] & mask) << 1)) >> bitPos;
                    Color color;

                    if(useCgb)
                        color = cgbSpriteColor(cgbPaletteId, pixel);
                    else
                        color = sgbSpriteColor(sgbPaletteId, pixel);

                    uint x;

                    if(xFlip)
                        x = xPos - xTile - 1;
                    else
                        x = xPos + xTile - 8;

                    if(x >= 0 && x < 160)
                    {
                        if(pixel != 0 && (!isBehind && !bgPriority[x] || tmpRawLine[x] == 0))
                        {
                            static if(tracing)
                                renderer.setPixel(x, y, Color(color.r/4+31, color.g/4+127, color.b/4+191));
                            else
                                renderer.setPixel(x, y, color);
                        }
                    }
                }
            }
        }
    }

    // Not synchronized with the LCD screen
    void vSyncInt()
    {
        cpu.addInterruptRequests(0b00000001);
    }

    void statInt()
    {
        cpu.addInterruptRequests(0b00000010);
    }

    // Determine if the LCD screen is switched on
    bool lcdOnFlag() const
    {
        immutable ubyte mask = 0b10000000;
        return (lcdControl & mask) != 0;
    }

    void lcdOnFlagSetting(bool value)
    {
        immutable ubyte mask = 0b10000000;

        if(value)
            lcdControl |= mask;
        else
            lcdControl &= ~mask;
    }

    // Determine the address of the map for the window
    bool windowMapBaseFlag() const
    {
        return (lcdControl & 0b01000000) != 0;
    }

    void windowMapBaseFlagSetting(bool value)
    {
        immutable ubyte mask = 0b01000000;

        if(value)
            lcdControl |= mask;
        else
            lcdControl &= ~mask;
    }

    // Determine if the window is displayed
    bool windowOnFlag() const
    {
        return (lcdControl & 0b00100000) != 0;
    }

    void windowOnFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00100000;

        if(value)
            lcdControl |= mask;
        else
            lcdControl &= ~mask;
    }

    // Determine the address of the tile data shared by both the background and the window
    bool bgAndWindowTileBaseFlag() const
    {
        immutable ubyte mask = 0b00010000;
        return (lcdControl & mask) != 0;
    }

    void bgAndWindowTileBaseFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00010000;

        if(value)
            lcdControl |= mask;
        else
            lcdControl &= ~mask;
    }

    // Determine the address of the map for the background
    bool bgMapBaseFlag() const
    {
        return (lcdControl & 0b00001000) != 0;
    }

    void bgMapBaseFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00001000;

        if(value)
            lcdControl |= mask;
        else
            lcdControl &= ~mask;
    }

    // Determine whether 8x8 or 8x16 sprites are displayed
    bool largeSpriteOnFlag() const
    {
        immutable ubyte mask = 0b00000100;
        return (lcdControl & mask) != 0;
    }

    void largeSpriteOnFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00000100;

        if(value)
            lcdControl |= mask;
        else
            lcdControl &= ~mask;
    }

    // Determine if the sprites are displayed
    bool spriteOnFlag() const
    {
        immutable ubyte mask = 0b00000010;
        return (lcdControl & mask) != 0;
    }

    void spriteOnFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00000010;

        if(value)
            lcdControl |= mask;
        else
            lcdControl &= ~mask;
    }

    // Determine if not the background is displayed
    bool bgOnFlag() const
    {
        immutable ubyte mask = 0b00000001;
        return (lcdControl & mask) != 0;
    }

    void bgOnFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00000001;

        if(value)
            lcdControl |= mask;
        else
            lcdControl &= ~mask;
    }

    bool lcdCoincidenceIntFlag() const
    {
        immutable ubyte mask = 0b01000000;
        return (lcdStatus & mask) != 0;
    }

    void lcdCoincidenceIntFlagSetting(bool value)
    {
        immutable ubyte mask = 0b01000000;

        if(value)
            lcdStatus |= mask;
        else
            lcdStatus &= ~mask;
    }

    bool lcdOamIntFlag() const
    {
        immutable ubyte mask = 0b00100000;
        return (lcdStatus & mask) != 0;
    }

    void lcdOamIntFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00100000;

        if(value)
            lcdStatus |= mask;
        else
            lcdStatus &= ~mask;
    }

    bool lcdVblankIntFlag() const
    {
        immutable ubyte mask = 0b00010000;
        return (lcdStatus & mask) != 0;
    }

    void lcdVblankIntFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00010000;

        if(value)
            lcdStatus |= mask;
        else
            lcdStatus &= ~mask;
    }

    bool lcdHblankIntFlag() const
    {
        immutable ubyte mask = 0b00001000;
        return (lcdStatus & mask) != 0;
    }

    void lcdHblankIntFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00001000;

        if(value)
            lcdStatus |= mask;
        else
            lcdStatus &= ~mask;
    }

    bool lcdCoincidenceFlag() const
    {
        immutable ubyte mask = 0b00000100;
        return (lcdStatus & mask) != 0;
    }

    void lcdCoincidenceFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00000100;

        if(value)
            lcdStatus |= mask;
        else
            lcdStatus &= ~mask;
    }

    ubyte lcdMode() const
    {
        immutable ubyte mask = 0b00000011;
        return lcdStatus & mask;
    }

    void lcdModeSetting(ubyte value)
    {
        immutable ubyte mask = 0b00000011;
        lcdStatus = (lcdStatus & (~mask)) | (value & mask);
    }
};


