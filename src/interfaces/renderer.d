module renderer;


struct Color
{
    ubyte r;
    ubyte g;
    ubyte b;
};


interface RendererItf
{
    public:

    int width() const;
    int height() const;
    Color pixel(int x, int y) const;
    void setPixel(int x, int y, Color color);
    const(Color)[] scanLine(int y) const;
    void setScanLine(int y, in Color[] color);
    const(ubyte)[] pixels() const;
};


