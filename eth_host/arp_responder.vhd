library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity arp_responder is
generic (
    DATA_WIDTH_BYTES : integer := 64
);
port (
    CLK                     : in  std_logic;
    RESET                   : in  std_logic;
    
    IS_ARP_PACKET           : in  std_logic;
    
    ARP_OPERATION           : in  std_logic_vector(15 downto 0);
    ARP_SHA                 : in  std_logic_vector(47 downto 0);
    ARP_SPA                 : in  std_logic_vector(31 downto 0);
    ARP_THA                 : in  std_logic_vector(47 downto 0);
    ARP_TPA                 : in  std_logic_vector(31 downto 0);
    HEADERS_PARSED          : in  std_logic;
    MY_MAC                  : in  std_logic_vector(47 downto 0);
    MY_IP                   : in  std_logic_vector(31 downto 0);
    M_AXIS_TREADY           : in  std_logic;
    
    M_AXIS_TDATA            : out std_logic_vector(DATA_WIDTH_BYTES*8-1 downto 0);
    M_AXIS_TKEEP            : out std_logic_vector(DATA_WIDTH_BYTES-1 downto 0);
    M_AXIS_TVALID           : out std_logic;
    M_AXIS_TLAST            : out std_logic;
    RESPONSE_SENT           : out std_logic
);
end entity arp_responder;

architecture arp_responder_arch of arp_responder is
    constant ARP_REQUEST_OP : std_logic_vector(15 downto 0) := x"0001";
    constant ARP_REPLY_OP   : std_logic_vector(15 downto 0) := x"0002";
    constant ETH_TYPE_ARP   : std_logic_vector(15 downto 0) := x"0806";
    constant RESPONSE_BYTES : integer := 42;
    constant DATA_BITS      : integer := DATA_WIDTH_BYTES * 8;

    signal pending          : std_logic;
    signal pending_sha      : std_logic_vector(47 downto 0);
    signal pending_spa      : std_logic_vector(31 downto 0);
    signal response_buffer  : std_logic_vector(RESPONSE_BYTES*8-1 downto 0);
    signal response_sent_reg: std_logic;

begin

    process(CLK)
    begin
        if rising_edge(CLK) then
                if HEADERS_PARSED = '1' and IS_ARP_PACKET = '1' and ARP_OPERATION = ARP_REQUEST_OP and ARP_TPA = MY_IP then
                    if pending = '0' then
                        pending <= '1';
                        pending_sha <= ARP_SHA;
                        pending_spa <= ARP_SPA;
                    end if;
                end if;

                if pending = '1' then
                    M_AXIS_TVALID <= '1';
                    M_AXIS_TDATA <= response_buffer & (DATA_BITS - RESPONSE_BYTES*8 - 1 downto 0 => '0');
                    M_AXIS_TKEEP <= (DATA_WIDTH_BYTES-1 downto DATA_WIDTH_BYTES-RESPONSE_BYTES => '1', others => '0');
                    M_AXIS_TLAST <= '1';
                    if M_AXIS_TREADY = '1' then
                        pending <= '0';
                        response_sent_reg <= '1';
                    end if;
                else
                    M_AXIS_TVALID <= '0';
                    M_AXIS_TLAST <= '0';
                    M_AXIS_TDATA <= (others => '0');
                    M_AXIS_TKEEP <= (others => '0');
                end if;
            end if;
    end process;

    process(CLK)
    begin
        response_buffer <= (others => '0');
        response_buffer(RESPONSE_BYTES*8-1 downto   RESPONSE_BYTES*8-48 ) <= pending_sha;
        response_buffer(RESPONSE_BYTES*8-49 downto  RESPONSE_BYTES*8-96 ) <= MY_MAC;
        response_buffer(RESPONSE_BYTES*8-97 downto  RESPONSE_BYTES*8-112) <= ETH_TYPE_ARP;
        response_buffer(RESPONSE_BYTES*8-113 downto RESPONSE_BYTES*8-128) <= x"0001";
        response_buffer(RESPONSE_BYTES*8-129 downto RESPONSE_BYTES*8-144) <= x"0800";
        response_buffer(RESPONSE_BYTES*8-145 downto RESPONSE_BYTES*8-152) <= x"06";
        response_buffer(RESPONSE_BYTES*8-153 downto RESPONSE_BYTES*8-160) <= x"04";
        response_buffer(RESPONSE_BYTES*8-161 downto RESPONSE_BYTES*8-176) <= ARP_REPLY_OP;
        response_buffer(RESPONSE_BYTES*8-177 downto RESPONSE_BYTES*8-224) <= MY_MAC;
        response_buffer(RESPONSE_BYTES*8-225 downto RESPONSE_BYTES*8-256) <= MY_IP;
        response_buffer(RESPONSE_BYTES*8-257 downto RESPONSE_BYTES*8-304) <= pending_sha;
        response_buffer(RESPONSE_BYTES*8-305 downto RESPONSE_BYTES*8-336) <= pending_spa;
    end process;

    RESPONSE_SENT <= response_sent_reg;

end arp_responder_arch;