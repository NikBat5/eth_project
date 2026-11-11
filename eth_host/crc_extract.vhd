library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity crc_extract is
    generic (
        DW_DATA : integer := 32  -- Byte
    );
    port (
        CLK            : in  std_logic;
        RESET          : in  std_logic;
        S_AXIS_TVALID  : in  std_logic;
        S_AXIS_TLAST   : in  std_logic;
        S_AXIS_TDATA   : in  std_logic_vector(DW_DATA*8-1 downto 0);
        PKT_LEN        : in  std_logic_vector(15 downto 0);
        CRC_OUT        : out std_logic_vector(31 downto 0);
        CRC_VALID      : out std_logic;
        CRC_FOUND      : out std_logic
    );
end crc_extract;

architecture rtl of crc_extract is

signal pkt_len_unsigned : unsigned(15 downto 0);          -- Packet length converted to unsigned
signal byte_cnt_reg     : unsigned(15 downto 0);          -- Byte counter - bytes received so far
signal curr_word_reg    : std_logic_vector(63 downto 0);  -- Current 64-bit data word
signal prev_word_reg    : std_logic_vector(63 downto 0);  -- Previous 64-bit data word (for CRC spanning across words)
signal crc_reg          : std_logic_vector(31 downto 0);  -- Extracted 32-bit CRC value
signal crc_valid_i      : std_logic;                      -- Output valid flag
signal crc_found_i      : std_logic;                      -- CRC found flag
signal byte_cnt_comb    : unsigned(15 downto 0);          -- Next byte count (current + DW_DATA)
signal diff_comb        : signed(15 downto 0);            -- Bytes counted - packet length (shows where CRC is)
signal crc_extracted    : std_logic;                      -- CRC extracted this cycle flag

begin

    pkt_len_unsigned <= unsigned(PKT_LEN);
    
    byte_cnt_comb <= byte_cnt_reg + to_unsigned(DW_DATA, 16);
    
    diff_comb <= signed(byte_cnt_comb) - signed(pkt_len_unsigned);

    process(CLK, RESET)
    begin
        if RESET = '1' then
            byte_cnt_reg   <= (others => '0');
            curr_word_reg  <= (others => '0');
            prev_word_reg  <= (others => '0');
            crc_reg        <= (others => '0');
            crc_valid_i    <= '0';
            crc_found_i    <= '0';
            crc_extracted  <= '0';
        elsif rising_edge(CLK) then
            crc_valid_i <= '0';
            crc_found_i <= '0';
            crc_extracted <= '0';

            if S_AXIS_TVALID = '1' then
                prev_word_reg <= curr_word_reg;
                curr_word_reg <= S_AXIS_TDATA;
                byte_cnt_reg <= byte_cnt_comb;

                if S_AXIS_TLAST = '1' then
                    if diff_comb >= 0 then
                        case to_integer(diff_comb(3 downto 0)) is
                            when 12 =>
                                crc_reg <= curr_word_reg(63 downto 32);-- diff_comb= - 14. all crc in curr_word_reg [63:32]
                                crc_extracted <= '1';
                            when 13 =>
                                crc_reg <= curr_word_reg(55 downto 32) & prev_word_reg(7 downto 0); -- diff_comb= - 3 crc 3B in curr_word_reg and 1B in prev_word_reg
                                crc_extracted <= '1';
                            when 14 =>
                                crc_reg <= curr_word_reg(47 downto 32) & prev_word_reg(15 downto 0); -- diff_comb= - 2 crc 2B in curr_word_reg and 2B in prev_word_reg
                                crc_extracted <= '1';
                            when 15 =>
                                crc_reg <= curr_word_reg(39 downto 32) & prev_word_reg(23 downto 0); --diff_comb= - 1 crc 1B in curr_word_reg and 3B in prev_word_reg
                                crc_extracted <= '1';
                            when 0 =>
                                crc_reg <= curr_word_reg(31 downto 0);  --diff_comb= 0 crc in prev_word_reg
                                crc_extracted <= '1';
                            when others =>
                                null;
                        end case;
                        
                        if crc_extracted = '1' then
                            crc_valid_i <= '1';
                            crc_found_i <= '1';
                        end if;
                        
                        byte_cnt_reg <= (others => '0');
                    end if;
                end if;
            end if;

            CRC_OUT   <= crc_reg;
            CRC_VALID <= crc_valid_i;
            CRC_FOUND <= crc_found_i;
        end if;
    end process;
end rtl;