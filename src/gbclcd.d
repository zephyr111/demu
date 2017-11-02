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
        const int offset = (x + 160*y) * 3;
        return Color(data[offset], data[offset+1], data[offset+2]);
    }

    void setPixel(int x, int y, Color color)
    {
        const int offset = (x + 160*y) * 3;
        data[offset+0] = color.r;
        data[offset+1] = color.g;
        data[offset+2] = color.b;
    }

    const(ubyte)[] pixels() const
    {
        return data;
    }
};


