library ieee;
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_arith.all; 
use IEEE.std_logic_unsigned.all; 

library xpm;
use xpm.vcomponents.all;



entity buffer_data is
generic (
    DATA_WIDTH_BYTES : integer := 64;
    BRAM_DEPTH       : integer := 4096
);
port (
    CLK                 : in std_logic;
    RESET               : in std_logic;
    S_AXIS_TDATA        : in std_logic_vector(DATA_WIDTH_BYTES*8 - 1 downto 0);
    S_AXIS_TKEEP        : in std_logic_vector(DATA_WIDTH_BYTES - 1 downto 0);
    S_AXIS_TVALID       : in std_logic;
    S_AXIS_TLAST        : in std_logic;
    S_AXIS_TREADY       : out std_logic;
    M_AXIS_TREADY       : in std_logic;
    M_AXIS_TDATA        : out std_logic_vector(DATA_WIDTH_BYTES*8 - 1 downto 0);
    M_AXIS_TKEEP        : out std_logic_vector(DATA_WIDTH_BYTES - 1 downto 0);
    M_AXIS_TVALID       : out std_logic;
    M_AXIS_TLAST        : out std_logic;
    TDEST_READY         : in std_logic;
    PACKET_FIELDS_VALID : in std_logic;
    IS_UDP_PACKET       : in std_logic;
    CRC_VALID           : in std_logic;
    UDP_DATA_BYTES      : in std_logic_vector(15 downto 0); 
    BRAM_FULL           : out std_logic;
    BRAM_EMPTY          : out std_logic;
    M_AXIS_TUSER        : out std_logic_vector(7 downto 0)
);

end buffer_data;

architecture buffer_data_arch of buffer_data is


    constant BRAM_BYTES      : integer := 8;
    constant BRAM_BITS       : integer := BRAM_BYTES * 8;
    constant NUM_BRAMS       : integer := (DATA_WIDTH_BYTES + BRAM_BYTES - 1) / BRAM_BYTES;
    constant ACTUAL_BYTES    : integer := NUM_BRAMS * BRAM_BYTES;
    constant ACTUAL_BITS     : integer := ACTUAL_BYTES * 8;
    constant ADDR_WIDTH      : integer := 12;
    
    type bram_data_array is array (0 to NUM_BRAMS-1) of std_logic_vector(BRAM_BITS-1 downto 0);
    signal bram_dout        : bram_data_array;
    
    signal wr_addr          : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal bram_rd_addr     : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    
    signal pkt_len_counter  : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal pkt_start_addr   : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal pkt_len          : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    
    signal rd_en_reg        : std_logic_vector(1 downto 0) := (others => '0');
    signal bram_rd_en_flag  : std_logic := '0';
    signal bram_rd_cnt      : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal data_valid_out   : std_logic := '0';
    signal tlast            : std_logic := '0';
    signal data_valid_out_d : std_logic := '0';
    signal tlast_d          : std_logic := '0';
    signal pkt_len_latched  : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal pkt_start_addr_latched : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => '0');
    
    signal packet_valid_reg : std_logic := '0';
    signal crc_valid_reg    : std_logic := '0';
    
    signal last_tkeep_reg   : std_logic_vector(ACTUAL_BYTES - 1 downto 0) := (others => '0');
    
    signal s_axis_tdata_aligned : std_logic_vector(ACTUAL_BITS - 1 downto 0) := (others => '0');
    signal s_axis_tkeep_aligned : std_logic_vector(ACTUAL_BYTES - 1 downto 0) := (others => '0');
    
    signal m_axis_tdata_int  : std_logic_vector(ACTUAL_BITS - 1 downto 0) := (others => '0');
    
    
    
component ila_buffer_all is
port (
    clk         : in std_logic;
    probe0      : in std_logic;                     
    probe1      : in std_logic_vector(11 downto 0);
    probe2      : in std_logic;
    probe3      : in std_logic;
    probe4      : in std_logic_vector(1 downto 0);
    probe5      : in std_logic;
    probe6      : in std_logic_vector(11 downto 0);
    probe7      : in std_logic;
    probe8      : in std_logic;
    probe9      : in std_logic_vector(511 downto 0);
    probe10     : in std_logic_vector(511 downto 0)
);
end component ila_buffer_all;



begin


ila_buffer_all_inst : ila_buffer_all
port map (
    clk         => CLK                      ,
    probe0      => S_AXIS_TVALID            ,                 
    probe1      => wr_addr                  ,
    probe2      => PACKET_FIELDS_VALID      ,
    probe3      => CRC_VALID                ,
    probe4      => rd_en_reg                ,
    probe5      => bram_rd_en_flag          ,
    probe6      => bram_rd_cnt              ,
    probe7      => data_valid_out           ,
    probe8      => data_valid_out_d         ,
    probe9      => S_AXIS_TDATA             ,
    probe10     => m_axis_tdata_int
);



    s_axis_tdata_aligned(ACTUAL_BITS-1 downto ACTUAL_BITS - DATA_WIDTH_BYTES*8) <= S_AXIS_TDATA;
    s_axis_tdata_aligned(ACTUAL_BITS - DATA_WIDTH_BYTES*8 - 1 downto 0) <= (others => '0');
    
    s_axis_tkeep_aligned(ACTUAL_BYTES-1 downto ACTUAL_BYTES - DATA_WIDTH_BYTES) <= S_AXIS_TKEEP;
    s_axis_tkeep_aligned(ACTUAL_BYTES - DATA_WIDTH_BYTES - 1 downto 0) <= (others => '0');

    gen_brams: for i in 0 to NUM_BRAMS-1 generate
        xpm_memory_sdpram_inst : xpm_memory_sdpram
        generic map (
            ADDR_WIDTH_A       => ADDR_WIDTH,
            ADDR_WIDTH_B       => ADDR_WIDTH,
            AUTO_SLEEP_TIME    => 0,
            BYTE_WRITE_WIDTH_A => 8,
            CASCADE_HEIGHT     => 0,
            CLOCKING_MODE      => "common_clock",
            ECC_MODE           => "no_ecc",
            MEMORY_INIT_FILE   => "none",
            MEMORY_INIT_PARAM  => "0",
            MEMORY_OPTIMIZATION => "true",
            MEMORY_PRIMITIVE   => "block",
            MEMORY_SIZE        => BRAM_DEPTH * BRAM_BITS,
            MESSAGE_CONTROL    => 0,
            READ_DATA_WIDTH_B  => BRAM_BITS,
            READ_LATENCY_B     => 2,
            READ_RESET_VALUE_B => "0",
            RST_MODE_A         => "SYNC",
            RST_MODE_B         => "SYNC",
            SIM_ASSERT_CHK     => 0,
            USE_EMBEDDED_CONSTRAINT => 0,
            USE_MEM_INIT       => 0,
            USE_MEM_INIT_MMI   => 0,
            WAKEUP_TIME        => "disable_sleep",
            WRITE_DATA_WIDTH_A => BRAM_BITS,
            WRITE_MODE_B       => "no_change",
            WRITE_PROTECT      => 1
        )
        port map (
            clka    => CLK,
            clkb    => CLK,
            ena     => S_AXIS_TVALID,
            wea     => s_axis_tkeep_aligned((i+1)*BRAM_BYTES-1 downto i*BRAM_BYTES),
            addra   => wr_addr,
            dina    => s_axis_tdata_aligned((i+1)*BRAM_BITS-1 downto i*BRAM_BITS),
            enb     => bram_rd_en_flag,
            addrb   => bram_rd_addr,
            doutb   => bram_dout(i),
            regceb  => '1',
            rstb    => RESET,
            sleep   => '0',
            injectdbiterra => '0',
            injectsbiterra => '0',
            dbiterrb => open,
            sbiterrb => open
        );
    end generate;

    process(CLK)
    begin
        if rising_edge(CLK) then
            for i in 0 to NUM_BRAMS-1 loop
                m_axis_tdata_int((i+1)*BRAM_BITS-1 downto i*BRAM_BITS) <= bram_dout(i);
            end loop;
        end if;
    end process;
    
    M_AXIS_TDATA <= m_axis_tdata_int(ACTUAL_BITS-1 downto ACTUAL_BITS - DATA_WIDTH_BYTES*8);

    write_process: process(CLK)
    begin
        if rising_edge(CLK) then
            if S_AXIS_TVALID = '1' then
                wr_addr <= wr_addr + 1;
                
                if S_AXIS_TLAST = '1' then
                    pkt_len_counter <= (others => '0');
                    last_tkeep_reg <= s_axis_tkeep_aligned;
                else
                    pkt_len_counter <= pkt_len_counter + 1;
                end if;
            end if;
                           
            if S_AXIS_TLAST = '1' then
                pkt_len <= pkt_len_counter + 1;
            end if;
                
            if S_AXIS_TLAST = '1' then 
                pkt_start_addr <= wr_addr - pkt_len_counter;
            end if;
        end if;
    end process;

    packet_valid_process: process(CLK)
    begin
        if rising_edge(CLK) then
            if PACKET_FIELDS_VALID = '1' then
                packet_valid_reg <= '1';
            elsif CRC_VALID = '1' then
                packet_valid_reg <= '0';
            end if;
        end if;
    end process;
    
    crc_valid_reg <= CRC_VALID;

    read_control: process(CLK)
    begin
        if rising_edge(CLK) then
            if PACKET_FIELDS_VALID = '1' then
                rd_en_reg(0) <= '1';
            elsif rd_en_reg = "11" then
                rd_en_reg(0) <= '0';
            end if;

            if CRC_VALID = '1' then
                rd_en_reg(1) <= '1';
            elsif rd_en_reg = "11" then
                rd_en_reg(1) <= '0';
            end if;

            bram_rd_en_flag <= rd_en_reg(0) and rd_en_reg(1);
        end if;
    end process;

    read_process: process(CLK)
    begin
        if rising_edge(CLK) then
            if bram_rd_en_flag = '1' and bram_rd_cnt = 0 then
                pkt_len_latched <= pkt_len;
                pkt_start_addr_latched <= pkt_start_addr;
                bram_rd_addr <= pkt_start_addr;
            end if;
            
            if bram_rd_en_flag = '1' then
                if bram_rd_cnt > 0 and bram_rd_cnt < pkt_len_latched then
                    bram_rd_addr <= bram_rd_addr + 1;
                end if;
                
                if bram_rd_cnt < pkt_len_latched then
                    bram_rd_cnt <= bram_rd_cnt + 1;
                end if;
            else
                bram_rd_cnt <= (others => '0');
            end if;
            
            if bram_rd_en_flag = '1' and bram_rd_cnt < pkt_len_latched then
                data_valid_out <= '1';
            else
                data_valid_out <= '0';
            end if;
            
            if bram_rd_cnt = pkt_len_latched - 1 then
                tlast <= '1';
            else
                tlast <= '0';
            end if;
        end if;
    end process;
    
    data_valid_out_d <= data_valid_out;
    tlast_d <= tlast;
    
    output_process: process(CLK)
    begin
        if rising_edge(CLK) then
                M_AXIS_TVALID <= data_valid_out_d;
                M_AXIS_TLAST <= tlast_d;
                if data_valid_out_d = '1' then
                    M_AXIS_TKEEP <= (others => '1');
                else
                    M_AXIS_TKEEP <= (others => '0');
                end if;
            end if;
        end process;

    S_AXIS_TREADY <= '1';
    M_AXIS_TUSER <= (others => '0');
    BRAM_FULL <= '0';
    BRAM_EMPTY <= '0';



end buffer_data_arch;
