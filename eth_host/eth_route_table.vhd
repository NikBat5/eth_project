library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
 

entity eth_route_table is
 generic (
        TABLE_SIZE : integer := 5;                                                     -- Number of entries in the lookup table
        DW_DATA : integer := 64                                              -- Width of AXIS data bus in bytes (64, 128, 256, 512)
          );
          port (
        -- Clock and reset signals
        CLK                  : in  std_logic                                      ; -- Main clock input
        RESET                : in  std_logic                                      ; -- Active low reset signal
        
        -- Packet header field inputs (extracted from incoming packets)
        DESTINATION_MAC        : in  std_logic_vector( 47 downto 0 )                ; -- Destination MAC address (6 bytes)
        SOURCE_MAC             : in  std_logic_vector( 47 downto 0 )                ; -- Source MAC address (6 bytes)
        ETHER_TYPE             : in  std_logic_vector( 15 downto 0 )                ; -- Ethernet type field (2 bytes)
        IP_VERSION             : in  std_logic_vector(  7 downto 0 )                ; -- IP version (1 byte)
        IP_PROTOCOL            : in  std_logic_vector(  7 downto 0 )                ; -- IP protocol (1 byte)
        IP_SOURCE_ADDR         : in  std_logic_vector( 31 downto 0 )                ; -- Source IP address (4 bytes)
        IP_DEST_ADDR           : in  std_logic_vector( 31 downto 0 )                ; -- Destination IP address (4 bytes)
        UDP_SOURCE_PORT        : in  std_logic_vector( 15 downto 0 )                ; -- UDP source port (2 bytes)
        UDP_DEST_PORT          : in  std_logic_vector( 15 downto 0 )                ; -- UDP destination port (2 bytes)
        UDP_SIGNAL_TABLE       : in  std_logic                                      ; -- Indicates if packet is UDP
        PACKET_FIELDS_VALID    : in  std_logic                                      ; -- Valid signal for all header fields
        CRC_VALID_IN           : in  std_logic                                      ; -- CRC validation result
        
        -- AXI Stream input interface (receiving packet data)
        S_AXIS_TDATA           : in  std_logic_vector( (DW_DATA*8)-1 downto 0 ); -- Input data bus
        S_AXIS_TKEEP           : in  std_logic_vector( DW_DATA-1 downto 0 );     -- Byte valid strobe
        S_AXIS_TVALID          : in  std_logic                                      ; -- Input data valid
        S_AXIS_TLAST           : in  std_logic                                      ; -- Last word of packet
        S_AXIS_TREADY          : out std_logic                                      ; -- Ready to receive data
        
        -- AXI Stream output interface (transmitting packet data)
        M_AXIS_TREADY          : in  std_logic                                      ; -- Output sink ready
        M_AXIS_TDATA           : out std_logic_vector( (DW_DATA*8)-1 downto 0 ); -- Output data bus
        M_AXIS_TKEEP           : out std_logic_vector( DW_DATA-1 downto 0 );     -- Output byte strobe
        M_AXIS_TVALID          : out std_logic                                      ; -- Output data valid
        M_AXIS_TLAST           : out std_logic                                      ; -- Last word of output packet
        M_AXIS_TDEST           : out std_logic_vector(  7 downto 0 )                ; -- Destination ID (match result)
        M_AXIS_TUSER           : out std_logic_vector(  7 downto 0 )                ; -- User sideband data
        
        -- AXI4-Lite configuration interface (for programming the lookup table)
        S_AXI_AWADDR           : in  std_logic_vector(  9 downto 0 )                ; -- Write address (10 bits)
        S_AXI_AWVALID          : in  std_logic                                      ; -- Write address valid
        S_AXI_AWREADY          : out std_logic                                      ; -- Write address ready
        S_AXI_WDATA            : in  std_logic_vector( 31 downto 0 )                ; -- Write data
        S_AXI_WSTRB            : in  std_logic_vector(  3 downto 0 )                ; -- Write strobe (byte enables)
        S_AXI_WVALID           : in  std_logic                                      ; -- Write data valid
        S_AXI_WREADY           : out std_logic                                      ; -- Write data ready
        S_AXI_BRESP            : out std_logic_vector(  1 downto 0 )                ; -- Write response
        S_AXI_BVALID           : out std_logic                                      ; -- Write response valid
        S_AXI_BREADY           : in  std_logic                                      ; -- Write response ready
        S_AXI_ARADDR           : in  std_logic_vector(  9 downto 0 )                ; -- Read address
        S_AXI_ARVALID          : in  std_logic                                      ; -- Read address valid
        S_AXI_ARREADY          : out std_logic                                      ; -- Read address ready
        S_AXI_RDATA            : out std_logic_vector( 31 downto 0 )                ; -- Read data
        S_AXI_RRESP            : out std_logic_vector(  1 downto 0 )                ; -- Read response
        S_AXI_RVALID           : out std_logic                                      ; -- Read data valid
        S_AXI_RREADY           : in  std_logic                                        -- Read data ready
    );

end eth_route_table;

architecture eth_route_table_arch of eth_route_table is

 component buffer_data is
        generic (
            DATA_WIDTH_BYTES : integer := 64
        );
        port (
            CLK                    : in  std_logic                                      ;
            RESET                : in  std_logic                                      ;
            S_AXIS_TDATA           : in  std_logic_vector( (DW_DATA*8)-1 downto 0 );
            S_AXIS_TKEEP           : in  std_logic_vector( DW_DATA-1 downto 0 );
            S_AXIS_TVALID          : in  std_logic                                      ;
            S_AXIS_TLAST           : in  std_logic                                      ;
            S_AXIS_TREADY          : out std_logic                                      ;
            M_AXIS_TREADY          : in  std_logic                                      ;
            M_AXIS_TDATA           : out std_logic_vector( (DW_DATA*8)-1 downto 0 );
            M_AXIS_TKEEP           : out std_logic_vector( DW_DATA-1 downto 0 );
            M_AXIS_TVALID          : out std_logic                                      ;
            M_AXIS_TLAST           : out std_logic                                      ;
            TDEST_READY            : in  std_logic                                      ;
            PACKET_FIELDS_VALID    : in  std_logic                                      ;
            IS_UDP_PACKET          : in  std_logic                                      ;
            CRC_VALID              : in  std_logic                                      ;
            UDP_DATA_BYTES         : in  std_logic_vector(15 downto 0)                  ;
            BRAM_FULL              : out std_logic                                      ;
            BRAM_EMPTY             : out std_logic                                      ;
            M_AXIS_TUSER           : out std_logic_vector( 7 downto 0)                    
        );
    end component;

    component up_axi is
        generic (
            AXI_ADDRESS_WIDTH : integer := 10                                           -- Address width for AXI interface
        );
        port (
            up_rstn          : in  std_logic                                            ;
            up_clk           : in  std_logic                                            ;
            up_axi_awvalid   : in  std_logic                                            ;
            up_axi_awaddr    : in  std_logic_vector( AXI_ADDRESS_WIDTH-1 downto 0 )     ;
            up_axi_awready   : out std_logic                                            ;
            up_axi_wvalid    : in  std_logic                                            ;
            up_axi_wdata     : in  std_logic_vector( 31 downto 0 )                      ;
            up_axi_wstrb     : in  std_logic_vector( 3 downto 0 )                       ;
            up_axi_wready    : out std_logic                                            ;
            up_axi_bvalid    : out std_logic                                            ;
            up_axi_bresp     : out std_logic_vector( 1 downto 0 )                       ;
            up_axi_bready    : in  std_logic                                            ;
            up_axi_arvalid   : in  std_logic                                            ;
            up_axi_araddr    : in  std_logic_vector( AXI_ADDRESS_WIDTH-1 downto 0 )     ;
            up_axi_arready   : out std_logic                                            ;
            up_axi_rvalid    : out std_logic                                            ;
            up_axi_rresp     : out std_logic_vector( 1 downto 0 )                       ;
            up_axi_rdata     : out std_logic_vector( 31 downto 0 )                      ;
            up_axi_rready    : in  std_logic                                            ;
            up_wreq          : out std_logic                                            ;
            up_waddr         : out std_logic_vector( AXI_ADDRESS_WIDTH-3 downto 0 )     ;
            up_wdata         : out std_logic_vector( 31 downto 0 )                      ;
            up_wstrb         : out std_logic_vector( 3 downto 0 )                       ;
            up_wack          : in  std_logic                                            ;
            up_rreq          : out std_logic                                            ;
            up_raddr         : out std_logic_vector( AXI_ADDRESS_WIDTH-3 downto 0 )     ;
            up_rdata         : in  std_logic_vector( 31 downto 0 )                      ;
            up_rack          : in  std_logic                                              
        );
    end component;

    -- Record type defining one entry in the lookup table
    type table_entry_type is record
        dst_mac         : std_logic_vector(63 downto 0);  -- Destination MAC (8 bytes, 6 used)
        src_mac         : std_logic_vector(63 downto 0);  -- Source MAC (8 bytes, 6 used)
        ether_type      : std_logic_vector(15 downto 0);  -- Ethernet type (2 bytes)
        ip_version      : std_logic_vector( 7 downto 0);  -- IP version (1 byte)
        ip_protocol     : std_logic_vector( 7 downto 0);  -- IP protocol (1 byte)
        ip_src_addr     : std_logic_vector(31 downto 0);  -- Source IP (4 bytes)
        ip_dst_addr     : std_logic_vector(31 downto 0);  -- Destination IP (4 bytes)
        udp_src_port    : std_logic_vector(15 downto 0);  -- UDP source port (2 bytes)
        udp_dst_port    : std_logic_vector(15 downto 0);  -- UDP destination port (2 bytes)
        valid           : std_logic_vector(15 downto 0);  -- Valid flags (lower bit enables entry)
        mask            : std_logic_vector(15 downto 0);  -- Mask bits for each field (9 fields used)
    end record;

    -- Array type for the lookup table
    type table_type is array (0 to TABLE_SIZE-1) of table_entry_type;
    -- Array type for match flags (one per entry, 9 flags per entry)
    type match_flags_type is array (0 to TABLE_SIZE-1) of std_logic_vector(8 downto 0);

    -- Signal declarations
    signal lookup_table : table_type;                                                   -- Main lookup table storage

    signal field_match_flags : match_flags_type;                                        -- Direct field comparison results
    signal mask_cond_flags   : match_flags_type;                                        -- Masked comparison results
    signal entry_match_flags : std_logic_vector(TABLE_SIZE-1 downto 0);                -- Entry match indicators

    signal packet_fields_valid_out : std_logic;                                         -- Delayed packet fields valid
    signal crc_valid_reg : std_logic;                                                   -- Registered CRC valid

    -- Registered header field values
    signal dst_mac_int      : std_logic_vector(63 downto 0) := (others => '0');        -- Internal dest MAC
    signal src_mac_int      : std_logic_vector(63 downto 0) := (others => '0');        -- Internal src MAC
    signal ether_type_int   : std_logic_vector(15 downto 0) := (others => '0');        -- Internal ether type
    signal ip_version_int   : std_logic_vector( 7 downto 0) := (others => '0');        -- Internal IP version
    signal ip_protocol_int  : std_logic_vector( 7 downto 0) := (others => '0');        -- Internal IP protocol
    signal ip_src_addr_int  : std_logic_vector(31 downto 0) := (others => '0');        -- Internal src IP
    signal ip_dst_addr_int  : std_logic_vector(31 downto 0) := (others => '0');        -- Internal dst IP
    signal udp_src_port_int : std_logic_vector(15 downto 0) := (others => '0');        -- Internal src port
    signal udp_dst_port_int : std_logic_vector(15 downto 0) := (others => '0');        -- Internal dst port

    -- Match result signals
    signal is_udp_packet_reg       : std_logic;                                         -- Registered UDP indicator
    signal match_found             : std_logic;                                         -- Match found flag
    signal current_match           : std_logic_vector(7 downto 0);                     -- Current match index (1-based)
    signal current_match_reg       : std_logic_vector(7 downto 0) := (others => '0'); -- Registered match index
    signal tdest_ready             : std_logic := '0';                                 -- TDEST ready signal for BRAM

    -- AXI to internal interface signals
    signal up_wreq          : std_logic;                                                -- Write request from up_axi
    signal up_waddr         : std_logic_vector(7 downto 0);                            -- Write address (8 bits, word aligned)
    signal up_wdata         : std_logic_vector(31 downto 0);                           -- Write data
    signal up_wstrb         : std_logic_vector(3 downto 0);                            -- Write strobe
    signal up_wack          : std_logic;                                                -- Write acknowledge to up_axi
    signal up_rreq          : std_logic;                                                -- Read request from up_axi
    signal up_raddr         : std_logic_vector(7 downto 0);                            -- Read address
    signal up_rdata         : std_logic_vector(31 downto 0);                           -- Read data to up_axi
    signal up_rack          : std_logic;                                                -- Read acknowledge to up_axi

    -- Write/read control signals
    signal up_wack_reg      : std_logic := '0';                                         -- Registered write acknowledge
    signal up_rack_reg      : std_logic := '0';                                         -- Registered read acknowledge
    signal up_rdata_reg     : std_logic_vector(31 downto 0) := (others => '0');        -- Read data register
    signal up_rdata_reg_d   : std_logic_vector(31 downto 0) := (others => '0');        -- Delayed read data
    signal active_entries   : integer range 0 to TABLE_SIZE := 0;                      -- Count of valid entries

    -- Delayed AXI requests for synchronization
    signal up_wreq_d        : std_logic := '0';                                         -- Delayed write request
    signal up_waddr_d       : std_logic_vector(7 downto 0) := (others => '0');         -- Delayed write address
    signal up_wdata_d       : std_logic_vector(31 downto 0) := (others => '0');        -- Delayed write data
    signal up_wstrb_d       : std_logic_vector(3 downto 0) := (others => '0');         -- Delayed write strobe
    signal up_rreq_d        : std_logic := '0';                                         -- Delayed read request
    signal up_raddr_d       : std_logic_vector(7 downto 0) := (others => '0');         -- Delayed read address

    -- Write operation state signals
    signal write_pending    : std_logic := '0';                                         -- Write operation pending
    signal write_address    : integer := 0;                                             -- Decoded write address
    signal read_address     : integer := 0;                                             -- Decoded read address
    signal write_entry_index : integer := 0;                                            -- Entry index for write (0 to TABLE_SIZE-1)
    signal write_field_index : integer := 0;                                            -- Field index within entry (0-8)
    signal read_entry_index  : integer := 0;                                            -- Entry index for read
    signal read_field_index  : integer := 0;                                            -- Field index for read
    signal temp_write_data   : std_logic_vector(31 downto 0) := (others => '0');        -- Temporary write data
    signal temp_write_strb   : std_logic_vector(3 downto 0) := (others => '0');         -- Temporary write strobe

    -- Operation completion flags
    signal write_done        : std_logic := '0';                                        -- Write operation complete
    signal read_done         : std_logic := '0';                                        -- Read operation complete
    signal write_active      : std_logic := '0';                                        -- Write operation active
    signal read_active       : std_logic := '0';                                        -- Read operation active
    signal read_pending      : std_logic := '0';                                        -- Read operation pending

component ila_table_headers is
port (
    clk         : in std_logic;
    probe0      : in std_logic;   -- is_udp_packet_reg
    probe1      : in std_logic_vector(63 downto 0);  --       dst_mac_int            
    probe2      : in std_logic_vector(63 downto 0);  --       src_mac_int            
    probe3      : in std_logic_vector(15 downto 0);  --    ether_type_int    
    probe4      : in std_logic_vector(7 downto 0);   --    ip_version_int    
    probe5      : in std_logic_vector(7 downto 0);   --   ip_protocol_int        
    probe6      : in std_logic_vector(31 downto 0);  --   ip_src_addr_int        
    probe7     : in std_logic_vector(31 downto 0);   --   ip_dst_addr_int    
    probe8     : in std_logic_vector(15 downto 0);   --  udp_src_port_int    
    probe9     : in std_logic_vector(15 downto 0);   --  udp_dst_port_int        
    probe10     : in std_logic                       -- S_AXIS_TVALID           
);
end component ila_table_headers;

begin

ila_table_headers_inst : ila_table_headers           
port map (                                     
    clk                 => CLK,                
    probe0              => PACKET_FIELDS_VALID  ,  
    probe1              =>      dst_mac_int   ,          
    probe2              =>      src_mac_int   ,             
    probe3              =>   ether_type_int   ,           
    probe4              =>   ip_version_int   ,      
    probe5              =>  ip_protocol_int   ,
    probe6              =>  ip_src_addr_int   ,            
    probe7              =>  ip_dst_addr_int   ,                 
    probe8              => udp_src_port_int   ,                 
    probe9              => udp_dst_port_int   ,                 
    probe10              => S_AXIS_TVALID
    );  

    -- Register CRC valid input
    crc_valid_reg <= CRC_VALID_IN;

    -- Process to capture and store packet header fields when valid
    process(CLK)
    begin
        if rising_edge(CLK) then
            packet_fields_valid_out <= PACKET_FIELDS_VALID;                             -- Forward valid signal
            if (PACKET_FIELDS_VALID = '1') then                                         -- When fields are valid
                dst_mac_int <= x"0000" & DESTINATION_MAC;                               -- Store dest MAC with padding
                src_mac_int <= x"0000" & SOURCE_MAC;                                    -- Store src MAC with padding
                ether_type_int <= ETHER_TYPE;                                           -- Store ether type
                ip_version_int <= "0000" & IP_VERSION(7 downto 4);                     -- Store only upper nibble
                ip_protocol_int <= IP_PROTOCOL;                                         -- Store IP protocol
                ip_src_addr_int <= IP_SOURCE_ADDR;                                      -- Store source IP
                ip_dst_addr_int <= IP_DEST_ADDR;                                        -- Store destination IP
                udp_src_port_int <= UDP_SOURCE_PORT;                                    -- Store UDP source port
                udp_dst_port_int <= UDP_DEST_PORT;                                      -- Store UDP destination port
            end if;
        end if;
    end process;

    -- Instantiate the BRAM controller for packet buffering
    buffer_data_inst : buffer_data
        generic map (
            DATA_WIDTH_BYTES => DW_DATA
        )
        port map (
            CLK                 => CLK,                                                 -- Connect clock
            RESET             => RESET,                                             -- Connect reset
            S_AXIS_TDATA        => S_AXIS_TDATA,                                        -- Connect input data
            S_AXIS_TKEEP        => S_AXIS_TKEEP,                                        -- Connect input keep
            S_AXIS_TVALID       => S_AXIS_TVALID,                                       -- Connect input valid
            S_AXIS_TLAST        => S_AXIS_TLAST,                                        -- Connect input last
            S_AXIS_TREADY       => S_AXIS_TREADY,                                       -- Connect input ready
            M_AXIS_TREADY       => M_AXIS_TREADY,                                       -- Connect output ready
            M_AXIS_TDATA        => M_AXIS_TDATA,                                        -- Connect output data
            M_AXIS_TKEEP        => M_AXIS_TKEEP,                                        -- Connect output keep
            M_AXIS_TVALID       => M_AXIS_TVALID,                                       -- Connect output valid
            M_AXIS_TLAST        => M_AXIS_TLAST,                                        -- Connect output last
            TDEST_READY         => tdest_ready,                                         -- Connect TDEST ready (match found)
            PACKET_FIELDS_VALID => packet_fields_valid_out,                             -- Connect fields valid
            IS_UDP_PACKET       => is_udp_packet_reg,                                   -- Connect UDP indicator
            CRC_VALID           => '1',                                       -- Connect CRC valid
            UDP_DATA_BYTES      => (others => '0'),                                     -- UDP data bytes not used
            BRAM_FULL           => open,                                                -- Not used
            BRAM_EMPTY          => open,                                                -- Not used
            M_AXIS_TUSER        => M_AXIS_TUSER                                         -- Connect output user data
        );

    -- Process to register UDP packet indicator
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     -- Reset condition
                is_udp_packet_reg <= '0';                                               -- Clear UDP indicator
            else
                is_udp_packet_reg <= UDP_SIGNAL_TABLE;                                  -- Store UDP indicator
            end if;
        end if;
    end process;

    -- Process to compare packet fields against each table entry
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     -- Reset condition
                field_match_flags <= (others => (others => '0'));                       -- Clear all match flags
            else
                -- Compare each field for all entries
                for i in 0 to TABLE_SIZE-1 loop
                    -- Compare destination MAC (bit 0 of match flags)
                    if (lookup_table(i).dst_mac = dst_mac_int) then
                        field_match_flags(i)(0) <= '1';                                 -- Match
                    else
                        field_match_flags(i)(0) <= '0';                                 -- No match
                    end if;
                    -- Compare source MAC (bit 1)
                    if (lookup_table(i).src_mac = src_mac_int) then
                        field_match_flags(i)(1) <= '1';
                    else
                        field_match_flags(i)(1) <= '0';
                    end if;
                    -- Compare ethernet type (bit 2)
                    if (lookup_table(i).ether_type = ether_type_int) then
                        field_match_flags(i)(2) <= '1';
                    else
                        field_match_flags(i)(2) <= '0';
                    end if;
                    -- Compare IP version (bit 3)
                    if (lookup_table(i).ip_version = ip_version_int) then
                        field_match_flags(i)(3) <= '1';
                    else
                        field_match_flags(i)(3) <= '0';
                    end if;
                    -- Compare IP protocol (bit 4)
                    if (lookup_table(i).ip_protocol = ip_protocol_int) then
                        field_match_flags(i)(4) <= '1';
                    else
                        field_match_flags(i)(4) <= '0';
                    end if;
                    -- Compare source IP address (bit 5)
                    if (lookup_table(i).ip_src_addr = ip_src_addr_int) then
                        field_match_flags(i)(5) <= '1';
                    else
                        field_match_flags(i)(5) <= '0';
                    end if;
                    -- Compare destination IP address (bit 6)
                    if (lookup_table(i).ip_dst_addr = ip_dst_addr_int) then
                        field_match_flags(i)(6) <= '1';
                    else
                        field_match_flags(i)(6) <= '0';
                    end if;
                    -- Compare UDP source port (bit 7)
                    if (lookup_table(i).udp_src_port = udp_src_port_int) then
                        field_match_flags(i)(7) <= '1';
                    else
                        field_match_flags(i)(7) <= '0';
                    end if;
                    -- Compare UDP destination port (bit 8)
                    if (lookup_table(i).udp_dst_port = udp_dst_port_int) then
                        field_match_flags(i)(8) <= '1';
                    else
                        field_match_flags(i)(8) <= '0';
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- Process to apply mask bits to field matches
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     -- Reset condition
                mask_cond_flags <= (others => (others => '0'));                         -- Clear masked flags
            else
                -- Apply mask for each entry and each field
                for i in 0 to TABLE_SIZE-1 loop
                    for j in 0 to 8 loop
                        if (lookup_table(i).mask(j) = '0') then                         -- If mask bit is 0 (don't care)
                            mask_cond_flags(i)(j) <= '1';                               -- Force match regardless
                        else                                                            -- If mask bit is 1 (care)
                            mask_cond_flags(i)(j) <= field_match_flags(i)(j);           -- Use actual match result
                        end if;
                    end loop;
                end loop;
            end if;
        end if;
    end process;

    -- Process to determine if entire entry matches
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     -- Reset condition
                entry_match_flags <= (others => '0');                                   -- Clear entry match flags
            else
                -- Check each entry for full match
                for i in 0 to TABLE_SIZE-1 loop
                    -- Entry matches if all 9 fields match (after mask) and entry is valid
                    if ((mask_cond_flags(i) = "111111111") and (lookup_table(i).valid(0) = '1')) then
                        entry_match_flags(i) <= '1';                                    -- Entry matches
                    else
                        entry_match_flags(i) <= '0';                                    -- Entry doesn't match
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- Process to find the first matching entry
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     
                match_found <= '0';                                                      
                current_match <= (others => '0');                                        
            else
                match_found <= '0';                                                      -- Default to no match
                current_match <= (others => '0');                                        -- Default to zero
                -- Search for first matching entry
                for i in 0 to TABLE_SIZE-1 loop
                    if (entry_match_flags(i) = '1') then                                 -- If entry matches
                        match_found <= '1';                                              -- Match found
                        current_match <= std_logic_vector(to_unsigned(i + 1, 8));        -- Store 1-based index
                        exit;                                                            -- Stop at first match
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- Process to generate TDEST ready signal for BRAM
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     -- Reset condition
                tdest_ready <= '0';                                                      -- Clear TDEST ready
            else
                tdest_ready <= match_found;                                              -- TDEST ready when match found
            end if;
        end if;
    end process;

    -- Process to register current match for output
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     -- Reset condition
                current_match_reg <= (others => '0');                                    -- Clear registered match
            else
                current_match_reg <= current_match;                                      -- Store current match
            end if;
        end if;
    end process;

    -- Process to delay AXI request signals for synchronization
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     
                up_wreq_d <= '0';                                                         -- Clear delayed write request
                up_waddr_d <= (others => '0');                                            -- Clear delayed write address
                up_wdata_d <= (others => '0');                                            -- Clear delayed write data
                up_wstrb_d <= (others => '0');                                            -- Clear delayed write strobe
                up_rreq_d <= '0';                                                         -- Clear delayed read request
                up_raddr_d <= (others => '0');                                            -- Clear delayed read address
            else
                up_wreq_d <= up_wreq;                                                    -- Delay write request
                up_waddr_d <= up_waddr;                                                  -- Delay write address
                up_wdata_d <= up_wdata;                                                  -- Delay write data
                up_wstrb_d <= up_wstrb;                                                  -- Delay write strobe
                up_rreq_d <= up_rreq;                                                    -- Delay read request
                up_raddr_d <= up_raddr;                                                  -- Delay read address
            end if;
        end if;
    end process;

    -- Process to handle write operations from AXI
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                      
                write_pending <= '0';                                                     -- Clear write pending
                write_address <= 0;                                                       -- Clear write address
                write_entry_index <= 0;                                                   -- Clear entry index
                write_field_index <= 0;                                                   -- Clear field index
                temp_write_data <= (others => '0');                                       -- Clear temp data
                temp_write_strb <= (others => '0');                                       -- Clear temp strobe
                write_active <= '0';                                                      -- Clear write active
                write_done <= '0';                                                        -- Clear write done
            else
                -- Check for new write request when not active
                if ((up_wreq_d = '1') and (write_active = '0') and (write_done = '0')) then
                    write_pending <= '1';                                               -- Set write pending
                    write_address <= to_integer(unsigned(up_waddr_d));                  -- Decode address
                    write_entry_index <= to_integer(unsigned(up_waddr_d)) / 9;          -- Calculate entry index
                    write_field_index <= to_integer(unsigned(up_waddr_d)) mod 9;        -- Calculate field index
                    temp_write_data <= up_wdata_d;                                      -- Store write data
                    temp_write_strb <= up_wstrb_d;                                      -- Store write strobe
                    write_active <= '1';                                                -- Set write active
                elsif (write_active = '1') then                                         -- If write is active
                    write_pending <= '0';                                               -- Clear write pending
                    write_done <= '1';                                                  -- Set write done
                    write_active <= '0';                                                -- Clear write active
                else
                    write_pending <= '0';                                                -- Clear write pending
                    if (write_done = '1') then                                           -- If write done was set
                        write_done <= '0';                                               -- Clear write done
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Process to handle read operations from AXI
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                      
                read_pending <= '0';                                                      -- Clear read pending
                read_address <= 0;                                                        -- Clear read address
                read_entry_index <= 0;                                                    -- Clear entry index
                read_field_index <= 0;                                                    -- Clear field index
                read_active <= '0';                                                       -- Clear read active
                read_done <= '0';                                                         -- Clear read done
            else
                -- Check for new read request when not active
                if ((up_rreq_d = '1') and (read_active = '0') and (read_done = '0')) then
                    read_pending <= '1';                                                 -- Set read pending
                    read_address <= to_integer(unsigned(up_raddr_d));                   -- Decode address
                    read_entry_index <= to_integer(unsigned(up_raddr_d)) / 9;           -- Calculate entry index
                    read_field_index <= to_integer(unsigned(up_raddr_d)) mod 9;         -- Calculate field index
                    read_active <= '1';                                                  -- Set read active
                elsif (read_active = '1') then                                           -- If read is active
                    read_pending <= '0';                                                 -- Clear read pending
                    read_done <= '1';                                                    -- Set read done
                    read_active <= '0';                                                  -- Clear read active
                else
                    read_pending <= '0';                                                 -- Clear read pending
                    if (read_done = '1') then                                            -- If read done was set
                        read_done <= '0';                                                -- Clear read done
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Process to generate write acknowledge
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                    
                up_wack_reg <= '0';                                                      -- Clear write acknowledge
            else
                if (write_done = '1') then                                               -- When write completes
                    up_wack_reg <= '1';                                                  -- Assert write acknowledge
                else
                    up_wack_reg <= '0';                                                  -- Deassert write acknowledge
                end if;
            end if;
        end if;
    end process;

    -- Process to generate read acknowledge
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     
                up_rack_reg <= '0';                                                       -- Clear read acknowledge
            else
                if (read_done = '1') then                                                -- When read completes
                    up_rack_reg <= '1';                                                  -- Assert read acknowledge
                else
                    up_rack_reg <= '0';                                                  -- Deassert read acknowledge
                end if;
            end if;
        end if;
    end process;

    -- Process to write data into lookup table based on field index
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (write_done = '1') then                                                   -- When write completes
                -- Check if address is within valid range
                if ((write_address < 9 * TABLE_SIZE) and (write_entry_index < TABLE_SIZE)) then
                    -- Select field based on field index
                    case write_field_index is
                        when 0 =>                                                        -- Field 0: Destination MAC lower 32 bits
                            if (temp_write_strb(0) = '1') then
                                lookup_table(write_entry_index).dst_mac(7 downto 0) <= temp_write_data(7 downto 0);
                            end if;
                            if (temp_write_strb(1) = '1') then
                                lookup_table(write_entry_index).dst_mac(15 downto 8) <= temp_write_data(15 downto 8);
                            end if;
                            if (temp_write_strb(2) = '1') then
                                lookup_table(write_entry_index).dst_mac(23 downto 16) <= temp_write_data(23 downto 16);
                            end if;
                            if (temp_write_strb(3) = '1') then
                                lookup_table(write_entry_index).dst_mac(31 downto 24) <= temp_write_data(31 downto 24);
                            end if;
                        when 1 =>                                                        -- Field 1: Destination MAC upper 32 bits (only lower 16 used)
                            if (temp_write_strb(0) = '1') then
                                lookup_table(write_entry_index).dst_mac(39 downto 32) <= temp_write_data(7 downto 0);
                            end if;
                            if (temp_write_strb(1) = '1') then
                                lookup_table(write_entry_index).dst_mac(47 downto 40) <= temp_write_data(15 downto 8);
                            end if;
                            if (temp_write_strb(2) = '1') then
                                lookup_table(write_entry_index).dst_mac(55 downto 48) <= temp_write_data(23 downto 16);
                            end if;
                            if (temp_write_strb(3) = '1') then
                                lookup_table(write_entry_index).dst_mac(63 downto 56) <= temp_write_data(31 downto 24);
                            end if;
                        when 2 =>                                                        -- Field 2: Source MAC lower 32 bits
                            if (temp_write_strb(0) = '1') then
                                lookup_table(write_entry_index).src_mac(7 downto 0) <= temp_write_data(7 downto 0);
                            end if;
                            if (temp_write_strb(1) = '1') then
                                lookup_table(write_entry_index).src_mac(15 downto 8) <= temp_write_data(15 downto 8);
                            end if;
                            if (temp_write_strb(2) = '1') then
                                lookup_table(write_entry_index).src_mac(23 downto 16) <= temp_write_data(23 downto 16);
                            end if;
                            if (temp_write_strb(3) = '1') then
                                lookup_table(write_entry_index).src_mac(31 downto 24) <= temp_write_data(31 downto 24);
                            end if;
                        when 3 =>                                                        -- Field 3: Source MAC upper 32 bits (only lower 16 used)
                            if (temp_write_strb(0) = '1') then
                                lookup_table(write_entry_index).src_mac(39 downto 32) <= temp_write_data(7 downto 0);
                            end if;
                            if (temp_write_strb(1) = '1') then
                                lookup_table(write_entry_index).src_mac(47 downto 40) <= temp_write_data(15 downto 8);
                            end if;
                            if (temp_write_strb(2) = '1') then
                                lookup_table(write_entry_index).src_mac(55 downto 48) <= temp_write_data(23 downto 16);
                            end if;
                            if (temp_write_strb(3) = '1') then
                                lookup_table(write_entry_index).src_mac(63 downto 56) <= temp_write_data(31 downto 24);
                            end if;
                        when 4 =>                                                        -- Field 4: Ethernet type, IP protocol, IP version
                            if (temp_write_strb(0) = '1') then
                                lookup_table(write_entry_index).ether_type(7 downto 0) <= temp_write_data(7 downto 0);
                            end if;
                            if (temp_write_strb(1) = '1') then
                                lookup_table(write_entry_index).ether_type(15 downto 8) <= temp_write_data(15 downto 8);
                            end if;
                            if (temp_write_strb(2) = '1') then
                                lookup_table(write_entry_index).ip_protocol <= temp_write_data(23 downto 16);
                            end if;
                            if (temp_write_strb(3) = '1') then
                                lookup_table(write_entry_index).ip_version <= temp_write_data(31 downto 24);
                            end if;
                        when 5 =>                                                        -- Field 5: Source IP address
                            if (temp_write_strb(0) = '1') then
                                lookup_table(write_entry_index).ip_src_addr(7 downto 0) <= temp_write_data(7 downto 0);
                            end if;
                            if (temp_write_strb(1) = '1') then
                                lookup_table(write_entry_index).ip_src_addr(15 downto 8) <= temp_write_data(15 downto 8);
                            end if;
                            if (temp_write_strb(2) = '1') then
                                lookup_table(write_entry_index).ip_src_addr(23 downto 16) <= temp_write_data(23 downto 16);
                            end if;
                            if (temp_write_strb(3) = '1') then
                                lookup_table(write_entry_index).ip_src_addr(31 downto 24) <= temp_write_data(31 downto 24);
                            end if;
                        when 6 =>                                                        -- Field 6: Destination IP address
                            if (temp_write_strb(0) = '1') then
                                lookup_table(write_entry_index).ip_dst_addr(7 downto 0) <= temp_write_data(7 downto 0);
                            end if;
                            if (temp_write_strb(1) = '1') then
                                lookup_table(write_entry_index).ip_dst_addr(15 downto 8) <= temp_write_data(15 downto 8);
                            end if;
                            if (temp_write_strb(2) = '1') then
                                lookup_table(write_entry_index).ip_dst_addr(23 downto 16) <= temp_write_data(23 downto 16);
                            end if;
                            if (temp_write_strb(3) = '1') then
                                lookup_table(write_entry_index).ip_dst_addr(31 downto 24) <= temp_write_data(31 downto 24);
                            end if;
                        when 7 =>                                                        -- Field 7: UDP ports (dest and src)
                            if (temp_write_strb(0) = '1') then
                                lookup_table(write_entry_index).udp_dst_port(7 downto 0) <= temp_write_data(7 downto 0);
                            end if;
                            if (temp_write_strb(1) = '1') then
                                lookup_table(write_entry_index).udp_dst_port(15 downto 8) <= temp_write_data(15 downto 8);
                            end if;
                            if (temp_write_strb(2) = '1') then
                                lookup_table(write_entry_index).udp_src_port(7 downto 0) <= temp_write_data(23 downto 16);
                            end if;
                            if (temp_write_strb(3) = '1') then
                                lookup_table(write_entry_index).udp_src_port(15 downto 8) <= temp_write_data(31 downto 24);
                            end if;
                        when 8 =>                                                        -- Field 8: Valid and mask bits
                            if (temp_write_strb(0) = '1') then
                                lookup_table(write_entry_index).valid(7 downto 0) <= temp_write_data(7 downto 0);
                            end if;
                            if (temp_write_strb(1) = '1') then
                                lookup_table(write_entry_index).valid(15 downto 8) <= temp_write_data(15 downto 8);
                            end if;
                            if (temp_write_strb(2) = '1') then
                                lookup_table(write_entry_index).mask(7 downto 0) <= temp_write_data(23 downto 16);
                            end if;
                            if (temp_write_strb(3) = '1') then
                                lookup_table(write_entry_index).mask(15 downto 8) <= temp_write_data(31 downto 24);
                            end if;
                        when others =>
                            null;                                                         -- Ignore invalid field indices
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- Process to count active (valid) entries in table
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     
                active_entries <= 0;                                                      -- Clear active count
            else
                -- Check each entry for valid bit changes
                for i in 0 to TABLE_SIZE-1 loop
                    -- If writing to valid field of this entry
                    if ((write_done = '1') and (write_field_index = 8) and (write_entry_index = i) and (temp_write_strb(0) = '1')) then
                        -- If setting valid from 0 to 1
                        if ((temp_write_data(0) = '1') and (lookup_table(i).valid(0) = '0')) then
                            active_entries <= active_entries + 1;                       -- Increment count
                        -- If clearing valid from 1 to 0
                        elsif ((temp_write_data(0) = '0') and (lookup_table(i).valid(0) = '1')) then
                            active_entries <= active_entries - 1;                       -- Decrement count
                        end if;
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- Process to read data from lookup table for AXI reads
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (read_done = '1') then                                                    -- When read completes
                -- Check for special status addresses
                if (read_address = 9 * TABLE_SIZE) then
                    up_rdata_reg <= (31 downto 1 => '0') & '1';                          -- Address returns 1 (version/ID)
                elsif (read_address = 9 * TABLE_SIZE + 1) then
                    up_rdata_reg <= std_logic_vector(to_unsigned(active_entries, 32));  -- Return active count
                -- Check if within table range
                elsif ((read_address < 9 * TABLE_SIZE) and (read_entry_index < TABLE_SIZE)) then
                    -- Select field based on field index
                    case read_field_index is
                        when 0 =>
                            up_rdata_reg <= lookup_table(read_entry_index).dst_mac(31 downto 0);  -- Dest MAC lower
                        when 1 =>
                            up_rdata_reg <= lookup_table(read_entry_index).dst_mac(63 downto 32); -- Dest MAC upper
                        when 2 =>
                            up_rdata_reg <= lookup_table(read_entry_index).src_mac(31 downto 0);  -- Src MAC lower
                        when 3 =>
                            up_rdata_reg <= lookup_table(read_entry_index).src_mac(63 downto 32); -- Src MAC upper
                        when 4 =>
                            -- Combine IP version, protocol, and ether type
                            up_rdata_reg <= lookup_table(read_entry_index).ip_version &
                                            lookup_table(read_entry_index).ip_protocol &
                                            lookup_table(read_entry_index).ether_type;
                        when 5 =>
                            up_rdata_reg <= lookup_table(read_entry_index).ip_src_addr;  -- Source IP
                        when 6 =>
                            up_rdata_reg <= lookup_table(read_entry_index).ip_dst_addr;  -- Dest IP
                        when 7 =>
                            -- Combine source and destination UDP ports
                            up_rdata_reg <= lookup_table(read_entry_index).udp_src_port &
                                            lookup_table(read_entry_index).udp_dst_port;
                        when 8 =>
                            -- Combine mask and valid fields
                            up_rdata_reg <= lookup_table(read_entry_index).mask &
                                            lookup_table(read_entry_index).valid;
                        when others =>
                            up_rdata_reg <= (others => '0');                             -- Return zeros for invalid
                    end case;
                else
                    up_rdata_reg <= (others => '0');                                     -- Return zeros for invalid addresses
                end if;
            end if;
        end if;
    end process;

    -- Process to delay read data for proper timing
    process(CLK)
    begin
        if rising_edge(CLK) then
            if (RESET = '0') then                                                     
                up_rdata_reg_d <= (others => '0');                                       -- Clear delayed read data
            else
                up_rdata_reg_d <= up_rdata_reg;                                          -- Delay read data by one cycle
            end if;
        end if;
    end process;

    -- Instantiate the AXI4-Lite to internal interface converter
    up_axi_inst : up_axi
        generic map (
            AXI_ADDRESS_WIDTH => 10                                                       -- 10-bit address width
        )
        port map (
            up_rstn         => RESET,                                                  
            up_clk          => CLK,                                                      
            up_axi_awvalid  => S_AXI_AWVALID,                                            
            up_axi_awaddr   => S_AXI_AWADDR,                                             
            up_axi_awready  => S_AXI_AWREADY,                                            
            up_axi_wvalid   => S_AXI_WVALID,                                             
            up_axi_wdata    => S_AXI_WDATA,                                              
            up_axi_wstrb    => S_AXI_WSTRB,                                              
            up_axi_wready   => S_AXI_WREADY,                                             
            up_axi_bvalid   => S_AXI_BVALID,                                             
            up_axi_bresp    => S_AXI_BRESP,                                              
            up_axi_bready   => S_AXI_BREADY,                                             
            up_axi_arvalid  => S_AXI_ARVALID,                                            
            up_axi_araddr   => S_AXI_ARADDR,                                             
            up_axi_arready  => S_AXI_ARREADY,                                            
            up_axi_rvalid   => S_AXI_RVALID,                                             
            up_axi_rresp    => S_AXI_RRESP,                                              
            up_axi_rdata    => S_AXI_RDATA,                                              
            up_axi_rready   => S_AXI_RREADY,                                             
            up_wreq         => up_wreq,                                                  
            up_waddr        => up_waddr,                                                 
            up_wdata        => up_wdata,                                                 
            up_wstrb        => up_wstrb,                                                 
            up_wack         => up_wack,                                                  
            up_rreq         => up_rreq,                                                  
            up_raddr        => up_raddr,                                                 
            up_rdata        => up_rdata,                                                 
            up_rack         => up_rack                                                   
        );

    -- Connect internal signals to up_axi interface
    up_wack <= up_wack_reg;                                                              
    up_rack <= up_rack_reg;                                                              
    up_rdata <= up_rdata_reg_d;                                                          

    -- Output the current match index as TDEST
    M_AXIS_TDEST <= current_match_reg;



end eth_route_table_arch;
