module gbcjoystick;

import interfaces.cpu;
import interfaces.joystick;


final class GbcJoystick : JoystickItf
{
    private:

    bool leftPressed;
    bool rightPressed;
    bool upPressed;
    bool downPressed;
    bool aPressed;
    bool bPressed;
    bool startPressed;
    bool selectPressed;
    bool genInterrupt;
    ubyte columnState;

    CpuItf cpu;


    public:

    void setLeft(bool pressed)
    {
        genInterrupt |= leftPressed != pressed;

        leftPressed = pressed;

        if(pressed)
            rightPressed = false;
    }

    void setRight(bool pressed)
    {
        genInterrupt |= rightPressed != pressed;

        rightPressed = pressed;

        if(pressed)
            leftPressed = false;
    }

    void setUp(bool pressed)
    {
        genInterrupt |= upPressed != pressed;

        upPressed = pressed;

        if(pressed)
            downPressed = false;
    }

    void setDown(bool pressed)
    {
        genInterrupt |= downPressed != pressed;

        downPressed = pressed;

        if(pressed)
            upPressed = false;
    }

    void setA(bool pressed)
    {
        genInterrupt |= aPressed != pressed;

        aPressed = pressed;
    }

    void setB(bool pressed)
    {
        genInterrupt |= bPressed != pressed;

        bPressed = pressed;
    }

    void setStart(bool pressed)
    {
        genInterrupt |= startPressed != pressed;

        startPressed = pressed;
    }

    void setSelect(bool pressed)
    {
        genInterrupt |= selectPressed != pressed;

        selectPressed = pressed;
    }

    bool left() const
    {
        return leftPressed;
    }

    bool right() const
    {
        return rightPressed;
    }

    bool up() const
    {
        return upPressed;
    }

    bool down() const
    {
        return downPressed;
    }

    bool a() const
    {
        return aPressed;
    }

    bool b() const
    {
        return bPressed;
    }

    bool start() const
    {
        return startPressed;
    }

    bool select() const
    {
        return selectPressed;
    }

    ubyte readState() const
    {
        ubyte state = 0b00001111;

        if(columnState & 0b00010000)
        {
            if(aPressed)
                state &= 0b1110;

            if(bPressed)
                state &= 0b1101;

            if(selectPressed)
                state &= 0b1011;

            if(startPressed)
                state &= 0b0111;
        }

        if(columnState & 0b00100000)
        {
            if(rightPressed)
                state &= 0b1110;

            if(leftPressed)
                state &= 0b1101;

            if(upPressed)
                state &= 0b1011;

            if(downPressed)
                state &= 0b0111;
        }

        return state;
    }

    void writeState(ubyte state)
    {
        columnState = state & 0b00110000;
    }

    void tick()
    {
        if(genInterrupt)
        {
            cpu.addInterruptRequests(0b00010000);
            genInterrupt = false;
        }
    }

    void connectCpu(CpuItf cpu)
    {
        this.cpu = cpu;
    }
};


