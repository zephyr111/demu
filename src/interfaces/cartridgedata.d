module cartridgedata;


enum CartridgeMmuType
{
    NONE,
    MBC1,
    MBC2,
    MBC3,
    MBC4,
    MBC5,
    HUC1,
    HUC3,
    MMM0,
    POCKET_CAMERA,
    BANDAI_TAMA5,
    UNKNOWN,
};


enum GameboyType
{
    NORMAL,
    SUPER,
    COLOR,
};


interface CartridgeDataItf
{
    public:

    // Title of the cartridge
    string title() const;

    // Four character uppercase corresponding to the manufacturer code
    string manufacturerCode() const;

    // Type of Game Boy required to use the cartridge (Game Boy Color, Super Game Boy, etc.)
    GameboyType requiredGameboy() const;

    // Indicate the company or publisher of the cartridge
    // For new cartridge (post normal game boy) : two characters (ASCII) 
    // For old cartridge : 8 bits
    ushort licenseCode() const;

    // Memory controler type used by the cartridge
    CartridgeMmuType memoryControlerType();

    // Size of the cartridge ROM (bytes)
    // Note: 1 byte = 1 octet 
    uint romSize() const;

    // Size of the cartridge RAM (bytes)
    // Note: 1 byte = 1 octet (if the controler used is not MBC2)
    uint ramSize() const;

    // Specifies if this version of the game is supposed to be sold in japan, or anywhere else
    bool japaneseVersion() const;

    // Raw content of the cartridge (BIOS + Header + ROM + etc.)
    const(ubyte)[] rawContent() const;
    ubyte[] rawContent();
};


