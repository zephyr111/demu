module cpuregister;

import std.bitmanip;


struct Register
{
    public:

    union
    {
        ushort all;
    
        version(LittleEndian)
        {
            struct
            {
                ubyte lo;
                ubyte hi;
            };
        }
        else
        {
            version(BigEndian)
            {
                struct
                {
                    ubyte hi;
                    ubyte lo;
                };
            }
            else
            {
                static assert(0, "Unknown endianness");
            }
        }
    }
};


