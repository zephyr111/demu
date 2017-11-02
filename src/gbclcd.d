module gcblcd;

import interfaces.renderer;


final class GbcLcd : RendererItf
{
    private:

    ubyte[160*144*3] data = 0x80;


    public:

    int width() const
    {
        return 160;
    }

    int height() const
    {
        return 144;
    }

    Color pixel(int x, int y) const
    {
        assert(x >= 0 && x < 160);
        assert(y >= 0 && y < 144);

        const int offset = (x + 160*y) * 3;
        return Color(data[offset], data[offset+1], data[offset+2]);
    }

    void setPixel(int x, int y, Color color)
    {
        assert(x >= 0 && x < 160);
        assert(y >= 0 && y < 144);

        const int offset = (x + 160*y) * 3;
        data[offset+0] = color.r;
        data[offset+1] = color.g;
        data[offset+2] = color.b;
    }

    const(Color)[] scanLine(int y) const
    {
        assert(y >= 0 && y < 144);

        const int offset = y*160*3;
        Color[] res = new Color[160];

        foreach(uint x ; 0..160)
        {
            res[x].r = data[offset+x*3+0];
            res[x].g = data[offset+x*3+1];
            res[x].b = data[offset+x*3+2];
        }

        return res;
    }

    void setScanLine(int y, in Color[] scanline)
    {
        assert(y >= 0 && y < 144);
        assert(scanline.length == 160);

        const int offset = y*160*3;

        static if(Color.sizeof == 3*ubyte.sizeof)
        {
            ubyte* src = cast(ubyte*)scanline.ptr;
            data[offset..offset+160*3] = src[0..160*3];
        }
        else
        {
            foreach(uint x ; 0..160)
            {
                data[offset+x*3+0] = scanline[x].r;
                data[offset+x*3+1] = scanline[x].g;
                data[offset+x*3+2] = scanline[x].b;
            }
        }
    }

    const(ubyte)[] pixels() const
    {
        return data;
    }
};


