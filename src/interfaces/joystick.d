module joystick;


interface JoystickItf
{
    public:

    void setLeft(bool pressed);
    void setRight(bool pressed);
    void setUp(bool pressed);
    void setDown(bool pressed);
    void setA(bool pressed);
    void setB(bool pressed);
    void setStart(bool pressed);
    void setSelect(bool pressed);

    bool left() const;
    bool right() const;
    bool up() const;
    bool down() const;
    bool a() const;
    bool b() const;
    bool start() const;
    bool select() const;

    ubyte readState() const;
    void writeState(ubyte state);
};


