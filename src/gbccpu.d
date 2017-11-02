module gbccpu;

import core.bitop;
import std.stdio;
import std.string;
import std.algorithm;
import std.range;
import std.typecons;
import std.conv;
import std.uni;

pragma(msg, "DEBUG");
import std.traits;

import interfaces.cpu;
import interfaces.mmu16b;
import cpuregister;
import reference;


// Note : 
//  - BCD flags not handled


pragma(msg, "TODO: support the halt bug");
pragma(msg, "TODO: support completely the stop instruction");
pragma(msg, "TODO: fully support the double speed mode (classic DMA should be two time faster, DMA to implement inside the CPU ?");
final class GbcCpu : CpuItf
{
    private:

    version(cpu_tracing)
        static immutable bool tracing = true;
    else
        static immutable bool tracing = false;

    immutable bool useCgb;
    Mmu16bItf mmu;
    Register af;
    Register bc;
    Register de;
    Register hl;
    Register pc;
    Register sp;
    ubyte imeFlag; // Interrupt master enable flag (mask)
    ubyte ifFlag; // Interrupt request flag
    ubyte ieFlag; // Interrupt enable flag
    bool halted;
    bool stopped;
    int remainingClock = 0; // Number of CPU cycle needed to execute the next instruction
    ubyte doubleSpeedMode;


    public:

    this(bool cgbMode)
    {
        useCgb = cgbMode;

        af.all = (cgbMode) ? 0x11B0 : 0x01B0;
        bc.all = 0x0013;
        de.all = 0x00D8;
        hl.all = 0x014D;
        pc.all = 0x0100;
        sp.all = 0xFFFE;

        imeFlag = 0x00; // value unspecified
        ifFlag = 0x00; // value unspecified
        ieFlag = 0x00;

        halted = false;
        stopped = false;
        doubleSpeedMode = 0x00;
    }

    ubyte doubleSpeedState()
    {
        return doubleSpeedMode;
    }

    void doubleSpeedRequest(ubyte value)
    {
        doubleSpeedSwitchFlagSetting((value & 0b00000001) != 0);
    }

    bool tick()
    {
        if(doubleSpeedFlag)
        {
            const bool resSubIter1 = internalTick();
            const bool resSubIter2 = internalTick();
            return resSubIter1 || resSubIter2;
        }
        else
        {
            return internalTick();
        }
    }

    bool internalTick()
    {
        // Check if an instruction is running
        if(remainingClock > 0)
        {
            remainingClock--;
            return true;
        }

        // Deals with interrupts (if occured)
        if(stopped)
        {
            if(doubleSpeedSwitchFlag)
            {
                doubleSpeedFlagSetting(!doubleSpeedFlag);
                doubleSpeedSwitchFlagSetting(false);
                remainingClock = 1<<17;
                stopped = false;

                pragma(msg, "DEBUG");
                writeln("switch to double speed mode & continue");
            }

            if((ifFlag & 0b00010000) != 0)
            {
                ifFlag = 0x00;
                remainingClock = 1<<17;
                stopped = false;

                pragma(msg, "DEBUG");
                writeln("continue");

                pragma(msg, "Disable interrupts here ?");
                //instruction_di();
            }
            else
            {
                remainingClock = 4 - 1;
            }

            return true;
        }
        else if(halted && imeFlag == 0)
        {
            if(ifFlag != 0)
            {
                pragma(msg, "DEBUG");
                writeln("continue");

                halted = false;
            }

            remainingClock = 4 - 1;
            return true;
        }
        else
        {
            const ubyte interruptState = imeFlag & ieFlag & ifFlag;

            if(interruptState != 0)
            {
                foreach_reverse(int i ; 0..5)
                {
                    if((interruptState & (0x01<<i)) != 0)
                    {
                        ifFlag &= ~(0x01<<i);
                        remainingClock = 20; // value unspecified

                        pragma(msg, "DEBUG");
                        if(halted)
                            writeln("continue");

                        halted = false;
                        pragma(msg, "Disable interrupts here ?");
                        instruction_di();
                        instruction_rst(0x40 + (i << 3));

                        return true;
                    }
                }
            }

            if(halted)
            {
                remainingClock = 4 - 1;
                return true;
            }
        }

        const ubyte instruction = mmu.loadByte(pc.all);
        int clockTaken = 4;

        switch(instruction)
        {
            case 0x00: assembly!"NOP"; clockTaken = 4; break;
            case 0x01: assembly!"LD bc, ushort"; clockTaken = 12; break;
            case 0x02: assembly!"LD [bc], a"; clockTaken = 8; break;
            case 0x03: assembly!"INC bc"; clockTaken = 8; break;
            case 0x04: assembly!"INC b"; clockTaken = 4; break;
            case 0x05: assembly!"DEC b"; clockTaken = 4; break;
            case 0x06: assembly!"LD b, ubyte"; clockTaken = 8; break;
            case 0x07: assembly!"RLCA"; clockTaken = 4; break;
            case 0x08: assembly!"LD [ushort], sp"; clockTaken = 20; break;
            case 0x09: assembly!"ADD hl, bc"; clockTaken = 8; break;
            case 0x0A: assembly!"LD a, [bc]"; clockTaken = 8; break;
            case 0x0B: assembly!"DEC bc"; clockTaken = 8; break;
            case 0x0C: assembly!"INC c"; clockTaken = 4; break;
            case 0x0D: assembly!"DEC c"; clockTaken = 4; break;
            case 0x0E: assembly!"LD c, ubyte"; clockTaken = 8; break;
            case 0x0F: assembly!"RRCA"; clockTaken = 4; break;
            case 0x10: assembly!"STOP"; break;
            case 0x11: assembly!"LD de, ushort"; clockTaken = 12; break;
            case 0x12: assembly!"LD [de], a"; clockTaken = 8; break;
            case 0x13: assembly!"INC de"; clockTaken = 8; break;
            case 0x14: assembly!"INC d"; clockTaken = 4; break;
            case 0x15: assembly!"DEC d"; clockTaken = 4; break;
            case 0x16: assembly!"LD d, ubyte"; clockTaken = 8; break;
            case 0x17: assembly!"RLA"; clockTaken = 4; break;
            case 0x18: assembly!"JR byte"; clockTaken = 12; break;
            case 0x19: assembly!"ADD hl, de"; clockTaken = 8; break;
            case 0x1A: assembly!"LD a, [de]"; clockTaken = 8; break;
            case 0x1B: assembly!"DEC de"; clockTaken = 8; break;
            case 0x1C: assembly!"INC e"; clockTaken = 4; break;
            case 0x1D: assembly!"DEC e"; clockTaken = 4; break;
            case 0x1E: assembly!"LD e, ubyte"; clockTaken = 8; break;
            case 0x1F: assembly!"RRA"; clockTaken = 4; break;

            case 0x20: assembly!"JR_NZ byte"; clockTaken = !zFlag ? 12 : 8; break;
            case 0x21: assembly!"LD hl, ushort"; clockTaken = 12; break;
            case 0x22: assembly!"LDI [hl], a"; clockTaken = 8; break;
            case 0x23: assembly!"INC hl"; clockTaken = 8; break;
            case 0x24: assembly!"INC h"; clockTaken = 4; break;
            case 0x25: assembly!"DEC h"; clockTaken = 4; break;
            case 0x26: assembly!"LD h, ubyte"; clockTaken = 8; break;
            case 0x27: assembly!"DAA"; clockTaken = 4; break;
            case 0x28: assembly!"JR_Z byte"; clockTaken = zFlag ? 12 : 8; break;
            case 0x29: assembly!"ADD hl, hl"; clockTaken = 8; break;
            case 0x2A: assembly!"LDI a, [hl]"; clockTaken = 8; break;
            case 0x2B: assembly!"DEC hl"; clockTaken = 8; break;
            case 0x2C: assembly!"INC l"; clockTaken = 4; break;
            case 0x2D: assembly!"DEC l"; clockTaken = 4; break;
            case 0x2E: assembly!"LD l, ubyte"; clockTaken = 8; break;
            case 0x2F: assembly!"CPL"; clockTaken = 4; break;

            case 0x30: assembly!"JR_NC byte"; clockTaken = !cFlag ? 12 : 8; break;
            case 0x31: assembly!"LD sp, ushort"; clockTaken = 12; break;
            case 0x32: assembly!"LDD [hl], a"; clockTaken = 8; break;
            case 0x33: assembly!"INC sp"; clockTaken = 8; break;
            case 0x34: assembly!"INC [hl]"; clockTaken = 12; break;
            case 0x35: assembly!"DEC [hl]"; clockTaken = 12; break;
            case 0x36: assembly!"LD [hl], ubyte"; clockTaken = 12; break;
            case 0x37: assembly!"SCF"; clockTaken = 4; break;
            case 0x38: assembly!"JR_C byte"; clockTaken = cFlag ? 12 : 8; break;
            case 0x39: assembly!"ADD hl, sp"; clockTaken = 8; break;
            case 0x3A: assembly!"LDD a, [hl]"; clockTaken = 8; break;
            case 0x3B: assembly!"DEC sp"; clockTaken = 8; break;
            case 0x3C: assembly!"INC a"; clockTaken = 4; break;
            case 0x3D: assembly!"DEC a"; clockTaken = 4; break;
            case 0x3E: assembly!"LD a, ubyte"; clockTaken = 8; break;
            case 0x3F: assembly!"CCF"; clockTaken = 4; break;

            case 0x40: assembly!"LD b, b"; clockTaken = 4; break;
            case 0x41: assembly!"LD b, c"; clockTaken = 4; break;
            case 0x42: assembly!"LD b, d"; clockTaken = 4; break;
            case 0x43: assembly!"LD b, e"; clockTaken = 4; break;
            case 0x44: assembly!"LD b, h"; clockTaken = 4; break;
            case 0x45: assembly!"LD b, l"; clockTaken = 4; break;
            case 0x46: assembly!"LD b, [hl]"; clockTaken = 8; break;
            case 0x47: assembly!"LD b, a"; clockTaken = 4; break;
            case 0x48: assembly!"LD c, b"; clockTaken = 4; break;
            case 0x49: assembly!"LD c, c"; clockTaken = 4; break;
            case 0x4A: assembly!"LD c, d"; clockTaken = 4; break;
            case 0x4B: assembly!"LD c, e"; clockTaken = 4; break;
            case 0x4C: assembly!"LD c, h"; clockTaken = 4; break;
            case 0x4D: assembly!"LD c, l"; clockTaken = 4; break;
            case 0x4E: assembly!"LD c, [hl]"; clockTaken = 8; break;
            case 0x4F: assembly!"LD c, a"; clockTaken = 4; break;

            case 0x50: assembly!"LD d, b"; clockTaken = 4; break;
            case 0x51: assembly!"LD d, c"; clockTaken = 4; break;
            case 0x52: assembly!"LD d, d"; clockTaken = 4; break;
            case 0x53: assembly!"LD d, e"; clockTaken = 4; break;
            case 0x54: assembly!"LD d, h"; clockTaken = 4; break;
            case 0x55: assembly!"LD d, l"; clockTaken = 4; break;
            case 0x56: assembly!"LD d, [hl]"; clockTaken = 8; break;
            case 0x57: assembly!"LD d, a"; clockTaken = 4; break;
            case 0x58: assembly!"LD e, b"; clockTaken = 4; break;
            case 0x59: assembly!"LD e, c"; clockTaken = 4; break;
            case 0x5A: assembly!"LD e, d"; clockTaken = 4; break;
            case 0x5B: assembly!"LD e, e"; clockTaken = 4; break;
            case 0x5C: assembly!"LD e, h"; clockTaken = 4; break;
            case 0x5D: assembly!"LD e, l"; clockTaken = 4; break;
            case 0x5E: assembly!"LD e, [hl]"; clockTaken = 8; break;
            case 0x5F: assembly!"LD e, a"; clockTaken = 4; break;

            case 0x60: assembly!"LD h, b"; clockTaken = 4; break;
            case 0x61: assembly!"LD h, c"; clockTaken = 4; break;
            case 0x62: assembly!"LD h, d"; clockTaken = 4; break;
            case 0x63: assembly!"LD h, e"; clockTaken = 4; break;
            case 0x64: assembly!"LD h, h"; clockTaken = 4; break;
            case 0x65: assembly!"LD h, l"; clockTaken = 4; break;
            case 0x66: assembly!"LD h, [hl]"; clockTaken = 8; break;
            case 0x67: assembly!"LD h, a"; clockTaken = 4; break;
            case 0x68: assembly!"LD l, b"; clockTaken = 4; break;
            case 0x69: assembly!"LD l, c"; clockTaken = 4; break;
            case 0x6A: assembly!"LD l, d"; clockTaken = 4; break;
            case 0x6B: assembly!"LD l, e"; clockTaken = 4; break;
            case 0x6C: assembly!"LD l, h"; clockTaken = 4; break;
            case 0x6D: assembly!"LD l, l"; clockTaken = 4; break;
            case 0x6E: assembly!"LD l, [hl]"; clockTaken = 8; break;
            case 0x6F: assembly!"LD l, a"; clockTaken = 4; break;

            case 0x70: assembly!"LD [hl], b"; clockTaken = 8; break;
            case 0x71: assembly!"LD [hl], c"; clockTaken = 8; break;
            case 0x72: assembly!"LD [hl], d"; clockTaken = 8; break;
            case 0x73: assembly!"LD [hl], e"; clockTaken = 8; break;
            case 0x74: assembly!"LD [hl], h"; clockTaken = 8; break;
            case 0x75: assembly!"LD [hl], l"; clockTaken = 8; break;
            case 0x76: assembly!"HALT"; break;
            case 0x77: assembly!"LD [hl], a"; clockTaken = 8; break;
            case 0x78: assembly!"LD a, b"; clockTaken = 4; break;
            case 0x79: assembly!"LD a, c"; clockTaken = 4; break;
            case 0x7A: assembly!"LD a, d"; clockTaken = 4; break;
            case 0x7B: assembly!"LD a, e"; clockTaken = 4; break;
            case 0x7C: assembly!"LD a, h"; clockTaken = 4; break;
            case 0x7D: assembly!"LD a, l"; clockTaken = 4; break;
            case 0x7E: assembly!"LD a, [hl]"; clockTaken = 8; break;
            case 0x7F: assembly!"LD a, a"; clockTaken = 4; break;

            case 0x80: assembly!"ADD a, b"; clockTaken = 4; break;
            case 0x81: assembly!"ADD a, c"; clockTaken = 4; break;
            case 0x82: assembly!"ADD a, d"; clockTaken = 4; break;
            case 0x83: assembly!"ADD a, e"; clockTaken = 4; break;
            case 0x84: assembly!"ADD a, h"; clockTaken = 4; break;
            case 0x85: assembly!"ADD a, l"; clockTaken = 4; break;
            case 0x86: assembly!"ADD a, [hl]"; clockTaken = 8; break;
            case 0x87: assembly!"ADD a, a"; clockTaken = 4; break;
            case 0x88: assembly!"ADC a, b"; clockTaken = 4; break;
            case 0x89: assembly!"ADC a, c"; clockTaken = 4; break;
            case 0x8A: assembly!"ADC a, d"; clockTaken = 4; break;
            case 0x8B: assembly!"ADC a, e"; clockTaken = 4; break;
            case 0x8C: assembly!"ADC a, h"; clockTaken = 4; break;
            case 0x8D: assembly!"ADC a, l"; clockTaken = 4; break;
            case 0x8E: assembly!"ADC a, [hl]"; clockTaken = 8; break;
            case 0x8F: assembly!"ADC a, a"; clockTaken = 4; break;

            case 0x90: assembly!"SUB a, b"; clockTaken = 4; break;
            case 0x91: assembly!"SUB a, c"; clockTaken = 4; break;
            case 0x92: assembly!"SUB a, d"; clockTaken = 4; break;
            case 0x93: assembly!"SUB a, e"; clockTaken = 4; break;
            case 0x94: assembly!"SUB a, h"; clockTaken = 4; break;
            case 0x95: assembly!"SUB a, l"; clockTaken = 4; break;
            case 0x96: assembly!"SUB a, [hl]"; clockTaken = 8; break;
            case 0x97: assembly!"SUB a, a"; clockTaken = 4; break;
            case 0x98: assembly!"SBC a, b"; clockTaken = 4; break;
            case 0x99: assembly!"SBC a, c"; clockTaken = 4; break;
            case 0x9A: assembly!"SBC a, d"; clockTaken = 4; break;
            case 0x9B: assembly!"SBC a, e"; clockTaken = 4; break;
            case 0x9C: assembly!"SBC a, h"; clockTaken = 4; break;
            case 0x9D: assembly!"SBC a, l"; clockTaken = 4; break;
            case 0x9E: assembly!"SBC a, [hl]"; clockTaken = 8; break;
            case 0x9F: assembly!"SBC a, a"; clockTaken = 4; break;

            case 0xA0: assembly!"AND b"; clockTaken = 4; break;
            case 0xA1: assembly!"AND c"; clockTaken = 4; break;
            case 0xA2: assembly!"AND d"; clockTaken = 4; break;
            case 0xA3: assembly!"AND e"; clockTaken = 4; break;
            case 0xA4: assembly!"AND h"; clockTaken = 4; break;
            case 0xA5: assembly!"AND l"; clockTaken = 4; break;
            case 0xA6: assembly!"AND [hl]"; clockTaken = 8; break;
            case 0xA7: assembly!"AND a"; clockTaken = 4; break;
            case 0xA8: assembly!"XOR b"; clockTaken = 4; break;
            case 0xA9: assembly!"XOR c"; clockTaken = 4; break;
            case 0xAA: assembly!"XOR d"; clockTaken = 4; break;
            case 0xAB: assembly!"XOR e"; clockTaken = 4; break;
            case 0xAC: assembly!"XOR h"; clockTaken = 4; break;
            case 0xAD: assembly!"XOR l"; clockTaken = 4; break;
            case 0xAE: assembly!"XOR [hl]"; clockTaken = 8; break;
            case 0xAF: assembly!"XOR a"; clockTaken = 4; break;

            case 0xB0: assembly!"OR b"; clockTaken = 4; break;
            case 0xB1: assembly!"OR c"; clockTaken = 4; break;
            case 0xB2: assembly!"OR d"; clockTaken = 4; break;
            case 0xB3: assembly!"OR e"; clockTaken = 4; break;
            case 0xB4: assembly!"OR h"; clockTaken = 4; break;
            case 0xB5: assembly!"OR l"; clockTaken = 4; break;
            case 0xB6: assembly!"OR [hl]"; clockTaken = 8; break;
            case 0xB7: assembly!"OR a"; clockTaken = 4; break;
            case 0xB8: assembly!"CP b"; clockTaken = 4; break;
            case 0xB9: assembly!"CP c"; clockTaken = 4; break;
            case 0xBA: assembly!"CP d"; clockTaken = 4; break;
            case 0xBB: assembly!"CP e"; clockTaken = 4; break;
            case 0xBC: assembly!"CP h"; clockTaken = 4; break;
            case 0xBD: assembly!"CP l"; clockTaken = 4; break;
            case 0xBE: assembly!"CP [hl]"; clockTaken = 8; break;
            case 0xBF: assembly!"CP a"; clockTaken = 4; break;

            case 0xC0: assembly!"RET_NZ"; clockTaken = !zFlag ? 20 : 8; break;
            case 0xC1: assembly!"POP bc"; clockTaken = 12; break;
            case 0xC2: assembly!"JP_NZ ushort"; clockTaken = !zFlag ? 16 : 12; break;
            case 0xC3: assembly!"JP ushort"; clockTaken = 16; break;
            case 0xC4: assembly!"CALL_NZ ushort"; clockTaken = !zFlag ? 24 : 12; break;
            case 0xC5: assembly!"PUSH bc"; clockTaken = 16; break;
            case 0xC6: assembly!"ADD a, ubyte"; clockTaken = 8; break;
            case 0xC7: assembly!"RST 0x00"; clockTaken = 16; break;
            case 0xC8: assembly!"RET_Z"; clockTaken = zFlag ? 20 : 8; break;
            case 0xC9: assembly!"RET"; clockTaken = 16; break;
            case 0xCA: assembly!"JP_Z ushort"; clockTaken = zFlag ? 16 : 12; break;
            case 0xCB: // Extended instructions
                const ubyte complement = mmu.loadByte(cast(ushort)(pc.all+1));
                switch(complement)
                {
                    case 0x00: assembly!"RLC b"; clockTaken = 8; break;
                    case 0x01: assembly!"RLC c"; clockTaken = 8; break;
                    case 0x02: assembly!"RLC d"; clockTaken = 8; break;
                    case 0x03: assembly!"RLC e"; clockTaken = 8; break;
                    case 0x04: assembly!"RLC h"; clockTaken = 8; break;
                    case 0x05: assembly!"RLC l"; clockTaken = 8; break;
                    case 0x06: assembly!"RLC [hl]"; clockTaken = 16; break;
                    case 0x07: assembly!"RLC a"; clockTaken = 8; break;
                    case 0x08: assembly!"RRC b"; clockTaken = 8; break;
                    case 0x09: assembly!"RRC c"; clockTaken = 8; break;
                    case 0x0A: assembly!"RRC d"; clockTaken = 8; break;
                    case 0x0B: assembly!"RRC e"; clockTaken = 8; break;
                    case 0x0C: assembly!"RRC h"; clockTaken = 8; break;
                    case 0x0D: assembly!"RRC l"; clockTaken = 8; break;
                    case 0x0E: assembly!"RRC [hl]"; clockTaken = 16; break;
                    case 0x0F: assembly!"RRC a"; clockTaken = 8; break;

                    case 0x10: assembly!"RL b"; clockTaken = 8; break;
                    case 0x11: assembly!"RL c"; clockTaken = 8; break;
                    case 0x12: assembly!"RL d"; clockTaken = 8; break;
                    case 0x13: assembly!"RL e"; clockTaken = 8; break;
                    case 0x14: assembly!"RL h"; clockTaken = 8; break;
                    case 0x15: assembly!"RL l"; clockTaken = 8; break;
                    case 0x16: assembly!"RL [hl]"; clockTaken = 16; break;
                    case 0x17: assembly!"RL a"; clockTaken = 8; break;
                    case 0x18: assembly!"RR b"; clockTaken = 8; break;
                    case 0x19: assembly!"RR c"; clockTaken = 8; break;
                    case 0x1A: assembly!"RR d"; clockTaken = 8; break;
                    case 0x1B: assembly!"RR e"; clockTaken = 8; break;
                    case 0x1C: assembly!"RR h"; clockTaken = 8; break;
                    case 0x1D: assembly!"RR l"; clockTaken = 8; break;
                    case 0x1E: assembly!"RR [hl]"; clockTaken = 16; break;
                    case 0x1F: assembly!"RR a"; clockTaken = 8; break;

                    case 0x20: assembly!"SLA b"; clockTaken = 8; break;
                    case 0x21: assembly!"SLA c"; clockTaken = 8; break;
                    case 0x22: assembly!"SLA d"; clockTaken = 8; break;
                    case 0x23: assembly!"SLA e"; clockTaken = 8; break;
                    case 0x24: assembly!"SLA h"; clockTaken = 8; break;
                    case 0x25: assembly!"SLA l"; clockTaken = 8; break;
                    case 0x26: assembly!"SLA [hl]"; clockTaken = 16; break;
                    case 0x27: assembly!"SLA a"; clockTaken = 8; break;
                    case 0x28: assembly!"SRA b"; clockTaken = 8; break;
                    case 0x29: assembly!"SRA c"; clockTaken = 8; break;
                    case 0x2A: assembly!"SRA d"; clockTaken = 8; break;
                    case 0x2B: assembly!"SRA e"; clockTaken = 8; break;
                    case 0x2C: assembly!"SRA h"; clockTaken = 8; break;
                    case 0x2D: assembly!"SRA l"; clockTaken = 8; break;
                    case 0x2E: assembly!"SRA [hl]"; clockTaken = 16; break;
                    case 0x2F: assembly!"SRA a"; clockTaken = 8; break;

                    case 0x30: assembly!"SWAP b"; clockTaken = 8; break;
                    case 0x31: assembly!"SWAP c"; clockTaken = 8; break;
                    case 0x32: assembly!"SWAP d"; clockTaken = 8; break;
                    case 0x33: assembly!"SWAP e"; clockTaken = 8; break;
                    case 0x34: assembly!"SWAP h"; clockTaken = 8; break;
                    case 0x35: assembly!"SWAP l"; clockTaken = 8; break;
                    case 0x36: assembly!"SWAP [hl]"; clockTaken = 16; break;
                    case 0x37: assembly!"SWAP a"; clockTaken = 8; break;
                    case 0x38: assembly!"SRL b"; clockTaken = 8; break;
                    case 0x39: assembly!"SRL c"; clockTaken = 8; break;
                    case 0x3A: assembly!"SRL d"; clockTaken = 8; break;
                    case 0x3B: assembly!"SRL e"; clockTaken = 8; break;
                    case 0x3C: assembly!"SRL h"; clockTaken = 8; break;
                    case 0x3D: assembly!"SRL l"; clockTaken = 8; break;
                    case 0x3E: assembly!"SRL [hl]"; clockTaken = 16; break;
                    case 0x3F: assembly!"SRL a"; clockTaken = 8; break;

                    case 0x40: assembly!"BIT 0, b"; clockTaken = 8; break;
                    case 0x41: assembly!"BIT 0, c"; clockTaken = 8; break;
                    case 0x42: assembly!"BIT 0, d"; clockTaken = 8; break;
                    case 0x43: assembly!"BIT 0, e"; clockTaken = 8; break;
                    case 0x44: assembly!"BIT 0, h"; clockTaken = 8; break;
                    case 0x45: assembly!"BIT 0, l"; clockTaken = 8; break;
                    case 0x46: assembly!"BIT 0, [hl]"; clockTaken = 12; break;
                    case 0x47: assembly!"BIT 0, a"; clockTaken = 8; break;
                    case 0x48: assembly!"BIT 1, b"; clockTaken = 8; break;
                    case 0x49: assembly!"BIT 1, c"; clockTaken = 8; break;
                    case 0x4A: assembly!"BIT 1, d"; clockTaken = 8; break;
                    case 0x4B: assembly!"BIT 1, e"; clockTaken = 8; break;
                    case 0x4C: assembly!"BIT 1, h"; clockTaken = 8; break;
                    case 0x4D: assembly!"BIT 1, l"; clockTaken = 8; break;
                    case 0x4E: assembly!"BIT 1, [hl]"; clockTaken = 12; break;
                    case 0x4F: assembly!"BIT 1, a"; clockTaken = 8; break;

                    case 0x50: assembly!"BIT 2, b"; clockTaken = 8; break;
                    case 0x51: assembly!"BIT 2, c"; clockTaken = 8; break;
                    case 0x52: assembly!"BIT 2, d"; clockTaken = 8; break;
                    case 0x53: assembly!"BIT 2, e"; clockTaken = 8; break;
                    case 0x54: assembly!"BIT 2, h"; clockTaken = 8; break;
                    case 0x55: assembly!"BIT 2, l"; clockTaken = 8; break;
                    case 0x56: assembly!"BIT 2, [hl]"; clockTaken = 12; break;
                    case 0x57: assembly!"BIT 2, a"; clockTaken = 8; break;
                    case 0x58: assembly!"BIT 3, b"; clockTaken = 8; break;
                    case 0x59: assembly!"BIT 3, c"; clockTaken = 8; break;
                    case 0x5A: assembly!"BIT 3, d"; clockTaken = 8; break;
                    case 0x5B: assembly!"BIT 3, e"; clockTaken = 8; break;
                    case 0x5C: assembly!"BIT 3, h"; clockTaken = 8; break;
                    case 0x5D: assembly!"BIT 3, l"; clockTaken = 8; break;
                    case 0x5E: assembly!"BIT 3, [hl]"; clockTaken = 12; break;
                    case 0x5F: assembly!"BIT 3, a"; clockTaken = 8; break;

                    case 0x60: assembly!"BIT 4, b"; clockTaken = 8; break;
                    case 0x61: assembly!"BIT 4, c"; clockTaken = 8; break;
                    case 0x62: assembly!"BIT 4, d"; clockTaken = 8; break;
                    case 0x63: assembly!"BIT 4, e"; clockTaken = 8; break;
                    case 0x64: assembly!"BIT 4, h"; clockTaken = 8; break;
                    case 0x65: assembly!"BIT 4, l"; clockTaken = 8; break;
                    case 0x66: assembly!"BIT 4, [hl]"; clockTaken = 12; break;
                    case 0x67: assembly!"BIT 4, a"; clockTaken = 8; break;
                    case 0x68: assembly!"BIT 5, b"; clockTaken = 8; break;
                    case 0x69: assembly!"BIT 5, c"; clockTaken = 8; break;
                    case 0x6A: assembly!"BIT 5, d"; clockTaken = 8; break;
                    case 0x6B: assembly!"BIT 5, e"; clockTaken = 8; break;
                    case 0x6C: assembly!"BIT 5, h"; clockTaken = 8; break;
                    case 0x6D: assembly!"BIT 5, l"; clockTaken = 8; break;
                    case 0x6E: assembly!"BIT 5, [hl]"; clockTaken = 12; break;
                    case 0x6F: assembly!"BIT 5, a"; clockTaken = 8; break;

                    case 0x70: assembly!"BIT 6, b"; clockTaken = 8; break;
                    case 0x71: assembly!"BIT 6, c"; clockTaken = 8; break;
                    case 0x72: assembly!"BIT 6, d"; clockTaken = 8; break;
                    case 0x73: assembly!"BIT 6, e"; clockTaken = 8; break;
                    case 0x74: assembly!"BIT 6, h"; clockTaken = 8; break;
                    case 0x75: assembly!"BIT 6, l"; clockTaken = 8; break;
                    case 0x76: assembly!"BIT 6, [hl]"; clockTaken = 12; break;
                    case 0x77: assembly!"BIT 6, a"; clockTaken = 8; break;
                    case 0x78: assembly!"BIT 7, b"; clockTaken = 8; break;
                    case 0x79: assembly!"BIT 7, c"; clockTaken = 8; break;
                    case 0x7A: assembly!"BIT 7, d"; clockTaken = 8; break;
                    case 0x7B: assembly!"BIT 7, e"; clockTaken = 8; break;
                    case 0x7C: assembly!"BIT 7, h"; clockTaken = 8; break;
                    case 0x7D: assembly!"BIT 7, l"; clockTaken = 8; break;
                    case 0x7E: assembly!"BIT 7, [hl]"; clockTaken = 12; break;
                    case 0x7F: assembly!"BIT 7, a"; clockTaken = 8; break;

                    case 0x80: assembly!"RES 0, b"; clockTaken = 8; break;
                    case 0x81: assembly!"RES 0, c"; clockTaken = 8; break;
                    case 0x82: assembly!"RES 0, d"; clockTaken = 8; break;
                    case 0x83: assembly!"RES 0, e"; clockTaken = 8; break;
                    case 0x84: assembly!"RES 0, h"; clockTaken = 8; break;
                    case 0x85: assembly!"RES 0, l"; clockTaken = 8; break;
                    case 0x86: assembly!"RES 0, [hl]"; clockTaken = 16; break;
                    case 0x87: assembly!"RES 0, a"; clockTaken = 8; break;
                    case 0x88: assembly!"RES 1, b"; clockTaken = 8; break;
                    case 0x89: assembly!"RES 1, c"; clockTaken = 8; break;
                    case 0x8A: assembly!"RES 1, d"; clockTaken = 8; break;
                    case 0x8B: assembly!"RES 1, e"; clockTaken = 8; break;
                    case 0x8C: assembly!"RES 1, h"; clockTaken = 8; break;
                    case 0x8D: assembly!"RES 1, l"; clockTaken = 8; break;
                    case 0x8E: assembly!"RES 1, [hl]"; clockTaken = 16; break;
                    case 0x8F: assembly!"RES 1, a"; clockTaken = 8; break;

                    case 0x90: assembly!"RES 2, b"; clockTaken = 8; break;
                    case 0x91: assembly!"RES 2, c"; clockTaken = 8; break;
                    case 0x92: assembly!"RES 2, d"; clockTaken = 8; break;
                    case 0x93: assembly!"RES 2, e"; clockTaken = 8; break;
                    case 0x94: assembly!"RES 2, h"; clockTaken = 8; break;
                    case 0x95: assembly!"RES 2, l"; clockTaken = 8; break;
                    case 0x96: assembly!"RES 2, [hl]"; clockTaken = 16; break;
                    case 0x97: assembly!"RES 2, a"; clockTaken = 8; break;
                    case 0x98: assembly!"RES 3, b"; clockTaken = 8; break;
                    case 0x99: assembly!"RES 3, c"; clockTaken = 8; break;
                    case 0x9A: assembly!"RES 3, d"; clockTaken = 8; break;
                    case 0x9B: assembly!"RES 3, e"; clockTaken = 8; break;
                    case 0x9C: assembly!"RES 3, h"; clockTaken = 8; break;
                    case 0x9D: assembly!"RES 3, l"; clockTaken = 8; break;
                    case 0x9E: assembly!"RES 3, [hl]"; clockTaken = 16; break;
                    case 0x9F: assembly!"RES 3, a"; clockTaken = 8; break;

                    case 0xA0: assembly!"RES 4, b"; clockTaken = 8; break;
                    case 0xA1: assembly!"RES 4, c"; clockTaken = 8; break;
                    case 0xA2: assembly!"RES 4, d"; clockTaken = 8; break;
                    case 0xA3: assembly!"RES 4, e"; clockTaken = 8; break;
                    case 0xA4: assembly!"RES 4, h"; clockTaken = 8; break;
                    case 0xA5: assembly!"RES 4, l"; clockTaken = 8; break;
                    case 0xA6: assembly!"RES 4, [hl]"; clockTaken = 16; break;
                    case 0xA7: assembly!"RES 4, a"; clockTaken = 8; break;
                    case 0xA8: assembly!"RES 5, b"; clockTaken = 8; break;
                    case 0xA9: assembly!"RES 5, c"; clockTaken = 8; break;
                    case 0xAA: assembly!"RES 5, d"; clockTaken = 8; break;
                    case 0xAB: assembly!"RES 5, e"; clockTaken = 8; break;
                    case 0xAC: assembly!"RES 5, h"; clockTaken = 8; break;
                    case 0xAD: assembly!"RES 5, l"; clockTaken = 8; break;
                    case 0xAE: assembly!"RES 5, [hl]"; clockTaken = 16; break;
                    case 0xAF: assembly!"RES 5, a"; clockTaken = 8; break;

                    case 0xB0: assembly!"RES 6, b"; clockTaken = 8; break;
                    case 0xB1: assembly!"RES 6, c"; clockTaken = 8; break;
                    case 0xB2: assembly!"RES 6, d"; clockTaken = 8; break;
                    case 0xB3: assembly!"RES 6, e"; clockTaken = 8; break;
                    case 0xB4: assembly!"RES 6, h"; clockTaken = 8; break;
                    case 0xB5: assembly!"RES 6, l"; clockTaken = 8; break;
                    case 0xB6: assembly!"RES 6, [hl]"; clockTaken = 16; break;
                    case 0xB7: assembly!"RES 6, a"; clockTaken = 8; break;
                    case 0xB8: assembly!"RES 7, b"; clockTaken = 8; break;
                    case 0xB9: assembly!"RES 7, c"; clockTaken = 8; break;
                    case 0xBA: assembly!"RES 7, d"; clockTaken = 8; break;
                    case 0xBB: assembly!"RES 7, e"; clockTaken = 8; break;
                    case 0xBC: assembly!"RES 7, h"; clockTaken = 8; break;
                    case 0xBD: assembly!"RES 7, l"; clockTaken = 8; break;
                    case 0xBE: assembly!"RES 7, [hl]"; clockTaken = 16; break;
                    case 0xBF: assembly!"RES 7, a"; clockTaken = 8; break;

                    case 0xC0: assembly!"SET 0, b"; clockTaken = 8; break;
                    case 0xC1: assembly!"SET 0, c"; clockTaken = 8; break;
                    case 0xC2: assembly!"SET 0, d"; clockTaken = 8; break;
                    case 0xC3: assembly!"SET 0, e"; clockTaken = 8; break;
                    case 0xC4: assembly!"SET 0, h"; clockTaken = 8; break;
                    case 0xC5: assembly!"SET 0, l"; clockTaken = 8; break;
                    case 0xC6: assembly!"SET 0, [hl]"; clockTaken = 16; break;
                    case 0xC7: assembly!"SET 0, a"; clockTaken = 8; break;
                    case 0xC8: assembly!"SET 1, b"; clockTaken = 8; break;
                    case 0xC9: assembly!"SET 1, c"; clockTaken = 8; break;
                    case 0xCA: assembly!"SET 1, d"; clockTaken = 8; break;
                    case 0xCB: assembly!"SET 1, e"; clockTaken = 8; break;
                    case 0xCC: assembly!"SET 1, h"; clockTaken = 8; break;
                    case 0xCD: assembly!"SET 1, l"; clockTaken = 8; break;
                    case 0xCE: assembly!"SET 1, [hl]"; clockTaken = 16; break;
                    case 0xCF: assembly!"SET 1, a"; clockTaken = 8; break;

                    case 0xD0: assembly!"SET 2, b"; clockTaken = 8; break;
                    case 0xD1: assembly!"SET 2, c"; clockTaken = 8; break;
                    case 0xD2: assembly!"SET 2, d"; clockTaken = 8; break;
                    case 0xD3: assembly!"SET 2, e"; clockTaken = 8; break;
                    case 0xD4: assembly!"SET 2, h"; clockTaken = 8; break;
                    case 0xD5: assembly!"SET 2, l"; clockTaken = 8; break;
                    case 0xD6: assembly!"SET 2, [hl]"; clockTaken = 16; break;
                    case 0xD7: assembly!"SET 2, a"; clockTaken = 8; break;
                    case 0xD8: assembly!"SET 3, b"; clockTaken = 8; break;
                    case 0xD9: assembly!"SET 3, c"; clockTaken = 8; break;
                    case 0xDA: assembly!"SET 3, d"; clockTaken = 8; break;
                    case 0xDB: assembly!"SET 3, e"; clockTaken = 8; break;
                    case 0xDC: assembly!"SET 3, h"; clockTaken = 8; break;
                    case 0xDD: assembly!"SET 3, l"; clockTaken = 8; break;
                    case 0xDE: assembly!"SET 3, [hl]"; clockTaken = 16; break;
                    case 0xDF: assembly!"SET 3, a"; clockTaken = 8; break;

                    case 0xE0: assembly!"SET 4, b"; clockTaken = 8; break;
                    case 0xE1: assembly!"SET 4, c"; clockTaken = 8; break;
                    case 0xE2: assembly!"SET 4, d"; clockTaken = 8; break;
                    case 0xE3: assembly!"SET 4, e"; clockTaken = 8; break;
                    case 0xE4: assembly!"SET 4, h"; clockTaken = 8; break;
                    case 0xE5: assembly!"SET 4, l"; clockTaken = 8; break;
                    case 0xE6: assembly!"SET 4, [hl]"; clockTaken = 16; break;
                    case 0xE7: assembly!"SET 4, a"; clockTaken = 8; break;
                    case 0xE8: assembly!"SET 5, b"; clockTaken = 8; break;
                    case 0xE9: assembly!"SET 5, c"; clockTaken = 8; break;
                    case 0xEA: assembly!"SET 5, d"; clockTaken = 8; break;
                    case 0xEB: assembly!"SET 5, e"; clockTaken = 8; break;
                    case 0xEC: assembly!"SET 5, h"; clockTaken = 8; break;
                    case 0xED: assembly!"SET 5, l"; clockTaken = 8; break;
                    case 0xEE: assembly!"SET 5, [hl]"; clockTaken = 16; break;
                    case 0xEF: assembly!"SET 5, a"; clockTaken = 8; break;

                    case 0xF0: assembly!"SET 6, b"; clockTaken = 8; break;
                    case 0xF1: assembly!"SET 6, c"; clockTaken = 8; break;
                    case 0xF2: assembly!"SET 6, d"; clockTaken = 8; break;
                    case 0xF3: assembly!"SET 6, e"; clockTaken = 8; break;
                    case 0xF4: assembly!"SET 6, h"; clockTaken = 8; break;
                    case 0xF5: assembly!"SET 6, l"; clockTaken = 8; break;
                    case 0xF6: assembly!"SET 6, [hl]"; clockTaken = 16; break;
                    case 0xF7: assembly!"SET 6, a"; clockTaken = 8; break;
                    case 0xF8: assembly!"SET 7, b"; clockTaken = 8; break;
                    case 0xF9: assembly!"SET 7, c"; clockTaken = 8; break;
                    case 0xFA: assembly!"SET 7, d"; clockTaken = 8; break;
                    case 0xFB: assembly!"SET 7, e"; clockTaken = 8; break;
                    case 0xFC: assembly!"SET 7, h"; clockTaken = 8; break;
                    case 0xFD: assembly!"SET 7, l"; clockTaken = 8; break;
                    case 0xFE: assembly!"SET 7, [hl]"; clockTaken = 16; break;
                    case 0xFF: assembly!"SET 7, a"; clockTaken = 8; break;

                    default:
                        throw new Exception("Unknown extended instruction (" ~ to!string(complement) ~ ")");
                }
                break;
            case 0xCC: assembly!"CALL_Z ushort"; clockTaken = zFlag ? 24 : 12; break;
            case 0xCD: assembly!"CALL ushort"; clockTaken = 24; break;
            case 0xCE: assembly!"ADC a, ubyte"; clockTaken = 8; break;
            case 0xCF: assembly!"RST 0x08"; clockTaken = 16; break;

            case 0xD0: assembly!"RET_NC"; clockTaken = !cFlag ? 20 : 8; break;
            case 0xD1: assembly!"POP de"; clockTaken = 12; break;
            case 0xD2: assembly!"JP_NC ushort"; clockTaken = !cFlag ? 16 : 12; break;
            //case 0xD3: No instruction
            case 0xD4: assembly!"CALL_NC ushort"; clockTaken = !cFlag ? 24 : 12; break;
            case 0xD5: assembly!"PUSH de"; clockTaken = 16; break;
            case 0xD6: assembly!"SUB a, ubyte"; clockTaken = 8; break;
            case 0xD7: assembly!"RST 0x10"; clockTaken = 16; break;
            case 0xD8: assembly!"RET_C"; clockTaken = cFlag ? 20 : 8; break;
            case 0xD9: assembly!"RETI"; clockTaken = 16; break;
            case 0xDA: assembly!"JP_C ushort"; clockTaken = cFlag ? 16 : 12; break;
            //case 0xDB: No instruction
            case 0xDC: assembly!"CALL_C ushort"; clockTaken = cFlag ? 24 : 12; break;
            //case 0xDD: No instruction
            case 0xDE: assembly!"SBC a, ubyte"; clockTaken = 8; break;
            case 0xDF: assembly!"RST 0x18"; clockTaken = 16; break;

            case 0xE0: assembly!"LD [0xFF00+ubyte], a"; clockTaken = 12; break;
            case 0xE1: assembly!"POP hl"; clockTaken = 12; break;
            case 0xE2: assembly!"LD [0xFF00+c], a"; clockTaken = 8; break;
            //case 0xE3: No instruction
            //case 0xE4: No instruction
            case 0xE5: assembly!"PUSH hl"; clockTaken = 16; break;
            case 0xE6: assembly!"AND ubyte"; clockTaken = 8; break;
            case 0xE7: assembly!"RST 0x20"; clockTaken = 16; break;
            case 0xE8: assembly!"ADD sp, byte"; clockTaken = 16; break;
            pragma(msg, "TODO: cf. issue with JP HL or JP [HL]")
            case 0xE9: assembly!"JP hl"; clockTaken = 4; break;
            case 0xEA: assembly!"LD [ushort], a"; clockTaken = 16; break;
            //case 0xEB: No instruction
            //case 0xEC: No instruction
            //case 0xED: No instruction
            case 0xEE: assembly!"XOR ubyte"; clockTaken = 8; break;
            case 0xEF: assembly!"RST 0x28"; clockTaken = 16; break;

            case 0xF0: assembly!"LD a, [0xFF00+ubyte]"; clockTaken = 12; break;
            case 0xF1: assembly!"POP af"; clockTaken = 12; break;
            case 0xF2: assembly!"LD a, [0xFF00+c]"; clockTaken = 8; break;
            case 0xF3: assembly!"DI"; clockTaken = 4; break;
            //case 0xF4: No instruction
            case 0xF5: assembly!"PUSH af"; clockTaken = 16; break;
            case 0xF6: assembly!"OR ubyte"; clockTaken = 8; break;
            case 0xF7: assembly!"RST 0x30"; clockTaken = 16; break;
            case 0xF8: assembly!"LDSP byte"; clockTaken = 12; break;
            case 0xF9: assembly!"LD sp, hl"; clockTaken = 8; break;
            case 0xFA: assembly!"LD a, [ushort]"; clockTaken = 16; break;
            case 0xFB: assembly!"EI"; clockTaken = 4; break;
            //case 0xFC: No instruction
            //case 0xFD: No instruction
            case 0xFE: assembly!"CP ubyte"; clockTaken = 8; break;
            case 0xFF: assembly!"RST 0x38"; clockTaken = 16; break;

            default:
                throw new Exception(format("Unknown instruction (opcode: 0x%0.2X, pc: 0x%0.4X)", instruction, pc.all));
        }

        static if(tracing)
        {
            writefln("trace/state/af:%0.2X %0.2X/bc:%0.2X %0.2X/de:%0.2X %0.2X/hl:%0.2X %0.2X/pc:%0.4X/sp:%0.4X", 
                    af.hi, af.lo, 
                    bc.hi, bc.lo,
                    de.hi, de.lo, 
                    hl.hi, hl.lo, 
                    pc.all, 
                    sp.all);
        }

        remainingClock = clockTaken - 1;
        return true;
    }

    void instruction_nop()
    {

    }

    void instruction_ld(T, U)(auto ref T op1, U op2)
    {
        static if(is(U == Reference))
            op1 = cast(T)op2;
        else
            op1 = op2;
    }

    void instruction_ldi(T, U)(auto ref T op1, U op2)
    {
        static if(is(U == Reference))
            op1 = cast(T)op2;
        else
            op1 = op2;

        hl.all++;
    }

    void instruction_ldd(T, U)(auto ref T op1, U op2)
    {
        static if(is(U == Reference))
            op1 = cast(T)op2;
        else
            op1 = op2;

        hl.all--;
    }

    void instruction_ldsp(byte op)
    {
        hl.all = cast(ushort)(sp.all + op);
        auto utmp = cast(ubyte)sp.all + cast(ubyte)op;
        cFlagSetting((utmp & 0xFFFFFF00) != 0);
        hFlagSetting(((sp.all ^ cast(ubyte)op ^ utmp) & 0x10) != 0);
        nFlagSetting(false);
        zFlagSetting(false);
    }

    void instruction_jp(T)(T op)
    {
        pc.all = cast(ushort)op;
    }

    void instruction_jp_z(T)(T op)
    {
        if(zFlag)
            instruction_jp(op);
    }

    void instruction_jp_nz(T)(T op)
    {
        if(!zFlag)
            instruction_jp(op);
    }

    void instruction_jp_c(T)(T op)
    {
        if(cFlag)
            instruction_jp(op);
    }

    void instruction_jp_nc(T)(T op)
    {
        if(!cFlag)
            instruction_jp(op);
    }

    void instruction_jr(T)(T op)
    {
        pc.all += cast(byte)op;
    }

    void instruction_jr_z(T)(T op)
    {
        if(zFlag)
            instruction_jr(op);
    }

    void instruction_jr_nz(T)(T op)
    {
        if(!zFlag)
            instruction_jr(op);
    }

    void instruction_jr_c(T)(T op)
    {
        if(cFlag)
            instruction_jr(op);
    }

    void instruction_jr_nc(T)(T op)
    {
        if(!cFlag)
            instruction_jr(op);
    }

    void instruction_inc(T)(auto ref T op)
    {
        static if(is(T == Reference))
        {
            auto tmpIn = cast(ubyte)op;
            auto tmp = cast(ubyte)(tmpIn + 1);
        }
        else
        {
            auto tmpIn = cast(T)op;
            auto tmp = cast(T)(tmpIn + 1);
        }

        op = tmp;

        static if(is(T == Reference) || is(T == ubyte) || is(T == byte))
        {
            hFlagSetting(((tmpIn ^ tmp) & 0x10) > 0);
            nFlagSetting(false);
            zFlagSetting(tmp == 0);
        }
    }

    void instruction_dec(T)(auto ref T op)
    {
        static if(is(T == Reference))
        {
            auto tmpIn = cast(ubyte)op;
            auto tmp = cast(ubyte)(tmpIn - 1);
        }
        else
        {
            auto tmpIn = cast(T)op;
            auto tmp = cast(T)(tmpIn - 1);
        }

        op = tmp;

        static if(is(T == Reference) || is(T == ubyte) || is(T == byte))
        {
            hFlagSetting(((tmpIn ^ tmp) & 0x10) > 0);
            nFlagSetting(true);
            zFlagSetting(tmp == 0);
        }
    }

    void instruction_rlca()
    {
        flagsSetting!("chnz", "");
        cFlagSetting((af.hi & 0x80) != 0);
        af.hi = rol!(1,ubyte)(af.hi);
    }

    void instruction_rla()
    {
        ubyte newBit = cFlag ? 0x01 : 0x00;
        flagsSetting!("chnz", "");
        cFlagSetting((af.hi & 0x80) != 0);
        af.hi = cast(ubyte)((af.hi << 1) | newBit);
    }

    void instruction_rrca()
    {
        flagsSetting!("chnz", "");
        cFlagSetting((af.hi & 0x01) != 0);
        af.hi = ror!(1,ubyte)(af.hi);
    }

    void instruction_rra()
    {
        ubyte newBit = cFlag ? 0x80 : 0x00;
        flagsSetting!("chnz", "");
        cFlagSetting((af.hi & 0x01) != 0);
        af.hi = cast(ubyte)((af.hi >> 1) | newBit);
    }

    void instruction_add(T, U)(auto ref T op1, U op2)
    {
        auto hfMask = (cast(T)0xFFFF >> 4) + 1;

        static if(is(U == Reference))
        {
            auto tmpIn = cast(T)op2;
            auto tmp = cast(T)(op1 + tmpIn);
            cFlagSetting(tmp < op1);
            hFlagSetting(((op1 ^ tmpIn ^ tmp) & hfMask) != 0);
        }
        else
        {
            static if(is(T == ushort) && is(U == byte))
            {
                auto tmp = op1 + op2;
                auto utmp = cast(ubyte)op1 + cast(ubyte)op2;
                cFlagSetting((utmp & 0xFFFFFF00) != 0);
                hFlagSetting(((op1 ^ cast(ubyte)op2 ^ utmp) & 0x10) != 0);
            }
            else
            {
                auto tmp = op1 + op2;
                cFlagSetting((tmp & (0xFFFFFFFF ^ cast(T)0xFFFF)) != 0);
                hFlagSetting(((op1 ^ op2 ^ tmp) & hfMask) != 0);
            }
        }

        op1 = cast(T)tmp;
        nFlagSetting(false);

        static if(is(T == ubyte))
            zFlagSetting(op1 == 0);
        else if(is(U == byte))
            zFlagSetting(false);
    }

    void instruction_adc(T, U)(auto ref T op1, U op2)
    {
        ubyte carry = cFlag ? 1 : 0;
        auto tmpIn = cast(T)op2;
        auto tmp = cast(T)(op1 + tmpIn + carry);
        auto hfMask = (cast(T)0xFFFF >> 4) + 1;
        cFlagSetting(tmp < cast(uint)op1 + carry);
        hFlagSetting(((op1 ^ tmpIn ^ tmp) & hfMask) != 0);
        op1 = tmp;
        nFlagSetting(false);
        zFlagSetting(tmp == 0);
    }

    void instruction_sub(T, U)(auto ref T op1, U op2)
    {
        auto tmpIn = cast(T)op2;
        auto tmp = cast(T)(op1 - tmpIn);
        auto hfMask = (cast(T)0xFFFF >> 4) + 1;
        cFlagSetting(tmp > op1);
        hFlagSetting(((op1 ^ tmpIn ^ tmp) & hfMask) != 0);
        op1 = tmp;
        nFlagSetting(true);
        zFlagSetting(tmp == 0);
    }

    void instruction_sbc(T, U)(auto ref T op1, U op2)
    {
        ubyte carry = cFlag ? 1 : 0;
        auto tmpIn = cast(T)op2;
        auto tmp = cast(T)(op1 - tmpIn - carry);
        auto hfMask = (cast(T)0xFFFF >> 4) + 1;
        cFlagSetting(tmp > cast(int)op1 - carry);
        hFlagSetting(((op1 ^ tmpIn ^ tmp) & hfMask) != 0);
        op1 = tmp;
        nFlagSetting(true);
        zFlagSetting(tmp == 0);
    }

    void instruction_cp(T)(T op)
    {
        auto tmpIn = cast(ubyte)op;
        auto tmp = cast(ubyte)(af.hi - tmpIn);
        cFlagSetting(tmp > af.hi);
        hFlagSetting(((af.hi ^ cast(ubyte)op ^ tmp) & 0x10) > 0);
        nFlagSetting(true);
        zFlagSetting(tmp == 0);
    }

    void instruction_and(T)(T op)
    {
        af.hi = af.hi & cast(ubyte)op;
        flagsSetting!("cnz", "h");
        zFlagSetting(af.hi == 0);
    }

    void instruction_or(T)(T op)
    {
        af.hi = af.hi | cast(ubyte)op;
        flagsSetting!("chnz", "");
        zFlagSetting(af.hi == 0);
    }

    void instruction_xor(T)(T op)
    {
        af.hi = af.hi ^ cast(ubyte)op;
        flagsSetting!("chnz", "");
        zFlagSetting(af.hi == 0);
    }

    void instruction_ccf()
    {
        cFlagSetting(!cFlag);
        flagsSetting!("hn", "");
    }

    void instruction_scf()
    {
        flagsSetting!("hn", "c");
    }

    void instruction_cpl()
    {
        af.hi ^= 0xFF;
        flagsSetting!("", "hn");
    }

    void instruction_daa()
    {
        int tmp = af.hi;

        if(!nFlag)
        {
            if(hFlag || (tmp & 0x0F) > 9)
                tmp += 0x06;

            if(cFlag || tmp > 0x9F)
                tmp += 0x60;
        }
        else
        {
            if(hFlag)
                tmp = (tmp - 6) & 0xFF;

            if(cFlag)
                tmp -= 0x60;
        }

        if((tmp & 0xFF00) != 0)
            cFlagSetting(true);

        af.hi = cast(ubyte)tmp;

        hFlagSetting(false);
        zFlagSetting(af.hi == 0);
    }

    void instruction_ei()
    {
        imeFlag = 0xFF;
    }

    void instruction_di()
    {
        imeFlag = 0x00;
    }

    void instruction_halt()
    {
        pragma(msg, "TODO: to check");
        //instruction_ei();
        halted = true;
        pragma(msg, "DEBUG");
        writeln("halted");
    }

    void instruction_stop()
    {
        pragma(msg, "TODO: to check");
        //instruction_ei();
        stopped = true;
        pragma(msg, "DEBUG");
        writeln("stopped");
    }

    void instruction_call(T)(T op)
    {
        sp.all -= 2;
        mmu.saveWord(sp.all, pc.all);
        pc.all = cast(ushort)op;
    }

    void instruction_call_z(T)(T op)
    {
        if(zFlag)
            instruction_call(op);
    }

    void instruction_call_nz(T)(T op)
    {
        if(!zFlag)
            instruction_call(op);
    }

    void instruction_call_c(T)(T op)
    {
        if(cFlag)
            instruction_call(op);
    }

    void instruction_call_nc(T)(T op)
    {
        if(!cFlag)
            instruction_call(op);
    }

    void instruction_rst(T)(T op)
    {
        instruction_call(op);
    }

    void instruction_ret()
    {
        pc.all = mmu.loadWord(sp.all);
        sp.all += 2;
    }

    void instruction_ret_z()
    {
        if(zFlag)
            instruction_ret();
    }

    void instruction_ret_nz()
    {
        if(!zFlag)
            instruction_ret();
    }

    void instruction_ret_c()
    {
        if(cFlag)
            instruction_ret();
    }

    void instruction_ret_nc()
    {
        if(!cFlag)
            instruction_ret();
    }

    void instruction_reti()
    {
        instruction_ei();
        instruction_ret();
    }

    void instruction_push(T)(T op)
    {
        sp.all -= 2;
        mmu.saveWord(sp.all, cast(ushort)op);
    }

    void instruction_pop(T)(auto ref T op)
    {
        op = mmu.loadWord(sp.all);
        sp.all += 2;

        // POP AF instruction cannot change the 4 lsb of the flag register as any instruction
        af.lo &= 0xF0;
    }

    void instruction_rlc(T)(auto ref T op)
    {
        ubyte value = cast(ubyte)op;
        cFlagSetting((value & 0x80) != 0);
        ubyte tmp = cast(ubyte)((value << 1) | (value >> 7));
        op = tmp;
        flagsSetting!("hn", "");
        zFlagSetting(tmp == 0);
    }

    void instruction_rrc(T)(auto ref T op)
    {
        ubyte value = cast(ubyte)op;
        cFlagSetting((value & 0x01) != 0);
        ubyte tmp = cast(ubyte)((value >> 1) | (value << 7));
        op = tmp;
        flagsSetting!("hn", "");
        zFlagSetting(tmp == 0);
    }

    void instruction_rl(T)(auto ref T op)
    {
        ubyte value = cast(ubyte)op;
        ubyte newBit = cFlag ? 0x01 : 0x00;
        cFlagSetting((value & 0x80) != 0);
        ubyte tmp = cast(ubyte)((value << 1) | newBit);
        op = tmp;
        flagsSetting!("hn", "");
        zFlagSetting(tmp == 0);
    }

    void instruction_rr(T)(auto ref T op)
    {
        ubyte value = cast(ubyte)op;
        ubyte newBit = cFlag ? 0x80 : 0x00;
        cFlagSetting((value & 0x01) != 0);
        ubyte tmp = cast(ubyte)((value >> 1) | newBit);
        op = tmp;
        flagsSetting!("hn", "");
        zFlagSetting(tmp == 0);
    }

    void instruction_sla(T)(auto ref T op)
    {
        ubyte value = cast(ubyte)op;
        cFlagSetting((value & 0x80) != 0);
        ubyte tmp = cast(ubyte)(value << 1);
        op = tmp;
        flagsSetting!("hn", "");
        zFlagSetting(tmp == 0);
    }

    void instruction_sra(T)(auto ref T op)
    {
        ubyte value = cast(ubyte)op;
        cFlagSetting((value & 0x01) != 0);
        ubyte tmp = cast(ubyte)(value >> 1 | value & 0x80);
        op = tmp;
        flagsSetting!("hn", "");
        zFlagSetting(tmp == 0);
    }

    void instruction_swap(T)(auto ref T op)
    {
        ubyte tmp = cast(ubyte)op;
        op = cast(ubyte)((tmp << 4) | (tmp >> 4));
        flagsSetting!("chnz", "");
        zFlagSetting(tmp == 0);
    }

    void instruction_srl(T)(auto ref T op)
    {
        ubyte value = cast(ubyte)op;
        cFlagSetting((value & 0x01) != 0);
        ubyte tmp = cast(ubyte)(value >> 1);
        op = tmp;
        flagsSetting!("hn", "");
        zFlagSetting(tmp == 0);
    }

    void instruction_bit(T, U)(T op1, auto ref U op2)
    {
        flagsSetting!("hn", "");
        hFlagSetting(true);
        nFlagSetting(false);
        zFlagSetting((cast(ubyte)op2 & (1<<op1)) == 0);
    }

    void instruction_res(T, U)(T op1, auto ref U op2)
    {
        op2 = cast(ubyte)(cast(ubyte)op2 & ~(1<<op1));
    }

    void instruction_set(T, U)(T op1, auto ref U op2)
    {
        op2 = cast(ubyte)(cast(ubyte)op2 | (1<<op1));
    }

    void addInterruptRequests(ubyte value)
    {
        ifFlag |= (value & 0x1F);
    }

    void setInterruptRequests(ubyte value)
    {
        ifFlag = value & 0x1F;
    }

    ubyte requestedInterrupts()
    {
        return ifFlag;
    }

    void enableInterrupts(ubyte value)
    {
        ieFlag = value & 0x1F;
    }

    ubyte enabledInterrupts()
    {
        return ieFlag;
    }

    void connectMmu(Mmu16bItf mmu)
    {
        this.mmu = mmu;
    }


    private:

    void assembly(string instructionCode)()
    {
        enum auto decoded = decodeInstruction(instructionCode);
        enum auto code = translateInstruction(decoded);
        enum auto increment = instructionSize(decoded);

        //pragma(msg, "Translation: instruction \"" ~ instructionCode ~ "\" convert to \"" ~ code ~ "\"")

        static if(tracing)
            writefln("trace/instruction/%0.4X/%s", pc.all, instructionCode);

        const ushort currentPc = pc.all;
        pc.all += increment;
        mixin(code);
    }

    static bool isAtomicOperand(string op)
    {
        auto isHexDigit = (dchar c) => "0123456789abcdef".canFind(c.toLower);
        return ["a", "b", "c", "d", "e", "h", "l", "af", "bc", "de", "hl", "sp", "pc", "ubyte", "byte", "ushort", "short"].canFind(op)
                    || op.length >= 3 && op[0..2] == "0x" && op[2..$].all!isHexDigit
                    || op.length >= 2 && op[$-1] == 'h' && op[0..$-1].all!isHexDigit
                    || op.length >= 1 && op.all!isNumber;
    }

    static Tuple!(string, string[]) decodeInstruction(in string instructionCode)
    {
        const auto parsed = instructionCode.toLower.strip.findSplitBefore(" ");
        const string opcode = parsed[0].strip;
        string[] args = std.algorithm.splitter(parsed[1]).filter!(s => !s.empty).map!(s => s.chomp(",").strip).array;

        if(!opcode[0].isAlpha || !opcode[$-1].isAlpha || !opcode.all!(s => s.isAlpha || s.isNumber || s == '_'))
            assert(0, "Bad name for the asm instruction \"" ~ instructionCode ~ "\"");

        // Check
        foreach(ref string arg ; args)
        {
            string id;
            bool fail = false;

            if(arg[0] == '[' && arg[$-1] == ']')
            {
                auto tmp = arg[1..$-1].strip.findSplit("+");
                auto atoms = [tmp[0], tmp[2]].map!strip.filter!(s => !s.empty);
                fail = fail || !atoms.all!(s => isAtomicOperand(s));
                arg = '[' ~ atoms.join("+") ~ ']';
            }
            else
                fail = !isAtomicOperand(arg);

            if(fail)
                assert(0, "Bad operand in the asm instruction \"" ~ instructionCode ~ "\"");
        }

        return Tuple!(string, string[])(opcode, args);
    }

    static int instructionSize(in Tuple!(string, string[]) decoded)
    {
        int instructionSize = 1;

        // Extended instructions
        if(["rlc", "rrc", "rl", "rr", "sla", "sra", "swap", "srl", "bit", "res", "set"].canFind(decoded[0]))
            instructionSize++;

        foreach(string arg ; decoded[1])
            if(arg.canFind("ubyte") || arg.canFind("byte"))
                instructionSize += 1;
            else if(arg.canFind("ushort") || arg.canFind("short"))
                instructionSize += 2;

        return instructionSize;
    }

    static string translateInstruction(in Tuple!(string, string[]) decoded)
    {
        const string opcode = decoded[0];
        const string[] args = decoded[1];
        const string params = args.map!(s => translateOperand(s)).join(", ");
        return "instruction_" ~ opcode ~ "(" ~ params ~ ");";
    }

    static string translateOperand(in string operand)
    {
        const string[string] byteRegisters = ["a":"af.hi", "f":"af.lo", "b":"bc.hi", "c":"bc.lo", "d":"de.hi", "e":"de.lo", "h":"hl.hi", "l":"hl.lo"];
        const string[string] shortRegisters = ["af":"af.all", "bc":"bc.all", "de":"de.all", "hl":"hl.all", "sp":"sp.all", "pc":"pc.all"];

        if(operand.length > 0 && operand[0] == '[' && operand[$-1] == ']')
        {
            auto tmp = operand[1..$-1].findSplit("+");
            const string params = [tmp[0], tmp[2]].filter!(s => !s.empty).map!(s => translateOperand(s)).join("+");
            return "Reference(mmu, cast(ushort)(" ~ params ~ "))";
        }
        else if(byteRegisters.keys.canFind(operand))
            return byteRegisters[operand];
        else if(shortRegisters.keys.canFind(operand))
            return shortRegisters[operand];
        else if(operand == "ubyte")
            return "cast(ubyte)mmu.loadByte(cast(ushort)(currentPc+1))";
        else if(operand == "byte")
            return "cast(byte)mmu.loadByte(cast(ushort)(currentPc+1))";
        else if(operand == "ushort")
            return "cast(ushort)mmu.loadWord(cast(ushort)(currentPc+1))";
        else if(operand == "short")
            return "cast(short)mmu.loadWord(cast(ushort)(currentPc+1))";
        else if(isAtomicOperand(operand))
            return operand;
        else
            assert(0, "Unable to recognize the operand \"" ~ operand ~ "\"");
    }

    bool zFlag() const
    {
        enum ubyte mask = genMask("z");
        return (af.lo & mask) != 0;
    }

    void zFlagSetting(bool set)
    {
        enum ubyte mask = genMask("z");

        if(set)
            af.lo |= mask;
        else
            af.lo &= ~mask;
    }

    bool nFlag() const
    {
        enum ubyte mask = genMask("n");
        return (af.lo & mask) != 0;
    }

    void nFlagSetting(bool set)
    {
        enum ubyte mask = genMask("n");

        if(set)
            af.lo |= mask;
        else
            af.lo &= ~mask;
    }

    bool hFlag() const
    {
        enum ubyte mask = genMask("h");
        return (af.lo & mask) != 0;
    }

    void hFlagSetting(bool set)
    {
        enum ubyte mask = genMask("h");

        if(set)
            af.lo |= mask;
        else
            af.lo &= ~mask;
    }

    bool cFlag() const
    {
        enum ubyte mask = genMask("c");
        return (af.lo & mask) != 0;
    }

    void cFlagSetting(bool set)
    {
        enum ubyte mask = genMask("c");

        if(set)
            af.lo |= mask;
        else
            af.lo &= ~mask;
    }

    static ubyte genMask(in string flags)
    {
        ubyte mask = 0b00000000;

        foreach(char flag ; flags)
        {
            if(flag == 'z')
                mask |= 0b10000000;
            else if(flag == 'n')
                mask |= 0b01000000;
            else if(flag == 'h')
                mask |= 0b00100000;
            else if(flag == 'c')
                mask |= 0b00010000;
            else
                assert(0, "Unknown input flag");
        }

        return mask;
    }

    void flagsSetting(string disabledFlags, string enabledFlags)()
    {
        enum ubyte downMask = ~genMask(disabledFlags);
        enum ubyte upMask = genMask(enabledFlags);
        enum string allFlags = disabledFlags ~ enabledFlags;

        static if(!allFlags.all!(a => (a == 'z' || a == 'n' || a == 'h' || a == 'c')))
            assert(0, "Unknown input flag");

        static if(allFlags.count("z") > 1 || allFlags.count("n") > 1 || allFlags.count("h") > 1 || allFlags.count("c") > 1)
            assert(0, "Duplicate input flag");

        static if(allFlags.length == 4)
        {
            af.lo = upMask;
        }
        else
        {
            static if(disabledFlags != "")
                af.lo &= downMask;

            static if(enabledFlags != "")
                af.lo |= upMask;
        }
    }

    bool doubleSpeedFlag() const
    {
        immutable ubyte mask = 0b10000000;

        return (doubleSpeedMode & mask) != 0;
    }

    void doubleSpeedFlagSetting(bool set)
    {
        immutable ubyte mask = 0b10000000;

        if(set)
            doubleSpeedMode |= mask;
        else
            doubleSpeedMode &= ~mask;
    }

    bool doubleSpeedSwitchFlag() const
    {
        immutable ubyte mask = 0b00000001;

        return (doubleSpeedMode & mask) != 0;
    }

    void doubleSpeedSwitchFlagSetting(bool set)
    {
        immutable ubyte mask = 0b00000001;

        if(set)
            doubleSpeedMode |= mask;
        else
            doubleSpeedMode &= ~mask;
    }
};


