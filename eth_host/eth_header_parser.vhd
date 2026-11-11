library ieee;
use ieee.std_logic_1164.all;
use IEEE.std_logic_arith.all;
use IEEE.std_logic_unsigned.all;


entity eth_header_parser is
generic (
    DW_DATA : integer := 64 -- byte
);
port (
    CLK                 : in std_logic                                      ; 
    RESET               : in std_logic                                      ;
    S_AXIS_TVALID       : in std_logic                                      ;-- Input data valid
    S_AXIS_TREADY       : in std_logic                                      ;
    S_AXIS_TDATA        : in std_logic_vector((DW_DATA*8)-1 downto 0)       ;-- Input data bus
    S_AXIS_TKEEP        : in std_logic_vector(DW_DATA-1 downto 0)           ;
    S_AXIS_TLAST        : in std_logic                                      ;

    IS_UDP_PACKET       : out std_logic                                     ;--UDP packets
    IS_ARP_PACKET       : out std_logic                                     ;--ARP packets
    
    ARP_REQUEST         : out std_logic                                     ;--ARP requests
    ARP_REPLY           : out std_logic                                     ;--ARP replies
    
    DA_FIELD            : out std_logic_vector( 47  downto 0    )           ;-- Destination MAC address   
    SA_FIELD            : out std_logic_vector( 47  downto 0    )           ;-- Source MAC address   
    ETHERTYPE_FIELD     : out std_logic_vector( 15  downto 0    )           ;-- EtherType field   
    IP_HEADER_FIELD     : out std_logic_vector( 159 downto 0    )           ;-- IPv4 header   
    UDP_HEADER_FIELD    : out std_logic_vector( 63  downto 0    )           ;-- UDP header   
    IP_PROTOCOL_HEADER  : out std_logic_vector(  7  downto 0    )           ;-- IPv4 protocol field   
    
    -- Additional IP fields
    IP_SOURCE_ADDR      : out std_logic_vector( 31  downto 0    )           ;-- IP source address
    IP_DEST_ADDR        : out std_logic_vector( 31  downto 0    )           ;-- IP destination address
    IP_IDENTIFICATION   : out std_logic_vector( 15  downto 0    )           ;-- IP identification
    IP_VERSION          : out std_logic_vector(  7  downto 0    )           ;-- IP version
    IP_HEADER_CHECKSUM  : out std_logic_vector( 15  downto 0    )           ;-- IP header checksum
    
    -- Additional UDP fields
    UDP_SOURCE_PORT     : out std_logic_vector( 15  downto 0    )           ;-- UDP source port
    UDP_DEST_PORT       : out std_logic_vector( 15  downto 0    )           ;-- UDP destination port
    UDP_LENGTH          : out std_logic_vector( 15  downto 0    )           ;-- UDP length
    
    -- ARP fields
    ARP_HTYPE_FIELD     : out std_logic_vector( 15  downto 0    )           ;-- Hardware type 
    ARP_PTYPE_FIELD     : out std_logic_vector( 15  downto 0    )           ;-- Protocol type  
    ARP_HLEN_FIELD      : out std_logic_vector(  7  downto 0    )           ;-- Hardware address length 
    ARP_PLEN_FIELD      : out std_logic_vector(  7  downto 0    )           ;-- Protocol address length 
    ARP_OPERATION_FIELD : out std_logic_vector( 15  downto 0    )           ;-- Operation               
    ARP_SHA_FIELD       : out std_logic_vector( 47  downto 0    )           ;-- Sender hardware address 
    ARP_SPA_FIELD       : out std_logic_vector( 31  downto 0    )           ;-- Sender protocol address 
    ARP_THA_FIELD       : out std_logic_vector( 47  downto 0    )           ;-- Target hardware address 
    ARP_TPA_FIELD       : out std_logic_vector( 31  downto 0    )           ;-- Target protocol address 
    
    HEADERS_PARSED      : out std_logic                                      --Pulse indicating all headers are captured and parsed
);

end eth_header_parser;

architecture eth_header_parser_arch of eth_header_parser is


    constant ETH_DST_MAC_LOW    : integer := 0;
    constant ETH_DST_MAC_HIGH   : integer := 47;
    constant ETH_SRC_MAC_LOW    : integer := 48;
    constant ETH_SRC_MAC_HIGH   : integer := 95;
    constant ETH_TYPE_LOW       : integer := 96;
    constant ETH_TYPE_HIGH      : integer := 111;
    
    -- IP header offsets 
    constant IP_VER_IHL_LOW     : integer := 112;
    constant IP_VER_IHL_HIGH    : integer := 119;
    constant IP_TOS_LOW         : integer := 120;
    constant IP_TOS_HIGH        : integer := 127;
    constant IP_TOTAL_LEN_LOW   : integer := 128;
    constant IP_TOTAL_LEN_HIGH  : integer := 143;
    constant IP_ID_LOW          : integer := 144;
    constant IP_ID_HIGH         : integer := 159;
    constant IP_FLAGS_FRAG_LOW  : integer := 160;
    constant IP_FLAGS_FRAG_HIGH : integer := 175;
    constant IP_TTL_LOW         : integer := 176;
    constant IP_TTL_HIGH        : integer := 183;
    constant IP_PROTO_LOW       : integer := 184;
    constant IP_PROTO_HIGH      : integer := 191;
    constant IP_CHECKSUM_LOW    : integer := 192;
    constant IP_CHECKSUM_HIGH   : integer := 207;
    constant IP_SRC_ADDR_LOW    : integer := 208;
    constant IP_SRC_ADDR_HIGH   : integer := 239;
    constant IP_DST_ADDR_LOW    : integer := 240;
    constant IP_DST_ADDR_HIGH   : integer := 271;
    
    -- UDP header offsets
    constant UDP_SRC_PORT_LOW    : integer := 272;
    constant UDP_SRC_PORT_HIGH   : integer := 287;
    constant UDP_DST_PORT_LOW    : integer := 288;
    constant UDP_DST_PORT_HIGH   : integer := 303;
    constant UDP_LEN_LOW         : integer := 304;
    constant UDP_LEN_HIGH        : integer := 319;
    constant UDP_CHECKSUM_LOW    : integer := 320;
    constant UDP_CHECKSUM_HIGH   : integer := 335;
    
    -- ARP header offsets
    constant ARP_HTYPE_LOW       : integer := 112;
    constant ARP_HTYPE_HIGH      : integer := 127;
    constant ARP_PTYPE_LOW       : integer := 128;
    constant ARP_PTYPE_HIGH      : integer := 143;
    constant ARP_HLEN_LOW        : integer := 144;
    constant ARP_HLEN_HIGH       : integer := 151;
    constant ARP_PLEN_LOW        : integer := 152;
    constant ARP_PLEN_HIGH       : integer := 159;
    constant ARP_OPER_LOW        : integer := 160;
    constant ARP_OPER_HIGH       : integer := 175;
    constant ARP_SHA_LOW         : integer := 176;
    constant ARP_SHA_HIGH        : integer := 223;
    constant ARP_SPA_LOW         : integer := 224;
    constant ARP_SPA_HIGH        : integer := 255;
    constant ARP_THA_LOW         : integer := 256;
    constant ARP_THA_HIGH        : integer := 303;
    constant ARP_TPA_LOW         : integer := 304;
    constant ARP_TPA_HIGH        : integer := 335;
    
    constant BIT_WIDTH      : integer := DW_DATA * 8                                    ; -- bit

    constant MAX_WIDTH      : integer := 512 * 8                                        ;
    
    constant TOTAL_BYTES    : integer := 42                                             ; -- Ethernet(14) + IPv4(20) + UDP(8) = 42 bytes
    constant TOTAL_BITS     : integer := TOTAL_BYTES * 8                                ;  
    constant ARP_TYPE       : std_logic_vector( 15 downto 0 ) := x"0806"                ; -- ARP EtherType
    constant IP_TYPE        : std_logic_vector( 15 downto 0 ) := x"0800"                ; -- IPv4 EtherType
    constant UDP_PROTOCOL   : std_logic_vector(  7 downto 0 ) := x"11"                  ; -- UDP protocol number
    
    -- ARP operation codes
    constant ARP_REQUEST_OP : std_logic_vector( 15 downto 0 ) := x"0001"                ; -- ARP request
    constant ARP_REPLY_OP   : std_logic_vector( 15 downto 0 ) := x"0002"                ; -- ARP reply
    
    constant TOTAL_TKEEP_BLOCKS : integer := DW_DATA / 4                                 ; -- number of 4-byte blocks in TKEEP
    constant ANALYZE_BLOCKS     : integer := TOTAL_TKEEP_BLOCKS                         ; -- analyze all blocks
    constant SKIP_BLOCKS        : integer := 0                                           ; -- start from first block
    
    -- Stage 0: Input registration
    signal s0_tdata         : std_logic_vector((DW_DATA*8)-1 downto 0)                  ;
    signal s0_tkeep         : std_logic_vector(DW_DATA-1 downto 0)                      ;
    signal s0_tvalid        : std_logic                                                 ;
    signal s0_tlast         : std_logic                                                 ;
    
    -- Stage 1: Coarse alignment
    type t_shift_4 is array (0 to ANALYZE_BLOCKS-1) of std_logic_vector(3 downto 0)     ;
    signal s1_tkeep_blocks      : t_shift_4                                             ; 
    signal s1_coarse_shift_val  : integer range 0 to (DW_DATA*8)-1                      ; -- bit
    signal s1_fine_win          : std_logic_vector(3 downto 0)                          ; 
    signal s1_tdata_shifted     : std_logic_vector((DW_DATA*8)-1 downto 0)              ; 
    signal s1_tvalid            : std_logic                                             ;
    signal s1_tlast             : std_logic                                             ;
    
    -- Stage 2: Fine alignment
    signal s2_fine_shift_val    : integer range 0 to 3                                  ; 
    signal s2_total_shift_val   : integer range 0 to (DW_DATA*8)-1                      ; -- bit
    signal s2_tdata_coarse      : std_logic_vector((DW_DATA*8)-1 downto 0)              ; 
    signal s2_tvalid            : std_logic                                             ;
    signal s2_tlast             : std_logic                                             ;
    
    -- Stage 3: Final aligned data
    signal s3_tdata_aligned     : std_logic_vector((DW_DATA*8)-1 downto 0)              ;
    signal s3_tvalid            : std_logic                                             ;
    signal s3_tlast             : std_logic                                             ;
    signal s3_total_shift_bits  : integer range 0 to (DW_DATA*8)-1                      ; -- bit
    
    -- Stage 4: Header accumulation
    signal header_buffer        : std_logic_vector(MAX_WIDTH -1 downto 0)                ;
    
    signal bit_cnt              : integer range 0 to MAX_WIDTH-1                        ;
    signal flag_data            : std_logic                                             ;
    
    -- Header registers
    signal da_reg               : std_logic_vector( 47  downto 0    )                   ;
    signal sa_reg               : std_logic_vector( 47  downto 0    )                   ;
    signal ethertype_reg        : std_logic_vector( 15  downto 0    )                   ;
    signal ip_header_reg        : std_logic_vector( 159 downto 0    )                   ;
    signal udp_header_reg       : std_logic_vector( 63  downto 0    )                   ;
    signal ip_protocol_reg      : std_logic_vector(  7  downto 0    )                   ;
    
    -- Additional IP registers
    signal ip_source_addr_reg   : std_logic_vector( 31  downto 0    )                   ;
    signal ip_dest_addr_reg     : std_logic_vector( 31  downto 0    )                   ;
    signal ip_identification_reg : std_logic_vector( 15  downto 0    )                  ;
    signal ip_version_reg       : std_logic_vector(  7  downto 0    )                   ;
    signal ip_header_checksum_reg : std_logic_vector( 15  downto 0    )                 ;
    
    -- Additional UDP registers
    signal udp_source_port_reg  : std_logic_vector( 15  downto 0    )                   ;
    signal udp_dest_port_reg    : std_logic_vector( 15  downto 0    )                   ;
    signal udp_length_reg       : std_logic_vector( 15  downto 0    )                   ;
    
    -- Packet type flags
    signal arp_ident            : std_logic                                             ;
    signal udp_identificator    : std_logic                                             ;
    
    -- ARP operation flags
    signal arp_request_flag     : std_logic                                             ;
    signal arp_reply_flag       : std_logic                                             ;
    
    -- ARP header registers
    signal arp_htype_reg        : std_logic_vector( 15  downto 0    )                   ;
    signal arp_ptype_reg        : std_logic_vector( 15  downto 0    )                   ;
    signal arp_hlen_reg         : std_logic_vector( 7   downto 0    )                   ;
    signal arp_plen_reg         : std_logic_vector( 7   downto 0    )                   ;
    signal arp_operation_reg    : std_logic_vector( 15  downto 0    )                   ;
    signal arp_sha_reg          : std_logic_vector( 47  downto 0    )                   ;
    signal arp_spa_reg          : std_logic_vector( 31  downto 0    )                   ;
    signal arp_tha_reg          : std_logic_vector( 47  downto 0    )                   ;
    signal arp_tpa_reg          : std_logic_vector( 31  downto 0    )                   ;
    
    -- Control signals
    signal headers_parsed_valid : std_logic                                             ;
    
    
component ila_parser_headers is
port (
    clk         : in std_logic;
    probe0      : in std_logic;   -- IS_UDP_PACKET
    probe1      : in std_logic;   -- IS_ARP_PACKET
    probe2      : in std_logic;   -- ARP_REQUEST
    probe3      : in std_logic;   -- ARP_REPLY
    probe4      : in std_logic_vector(47 downto 0);  -- DA_FIELD
    probe5      : in std_logic_vector(47 downto 0);  -- SA_FIELD
    probe6      : in std_logic_vector(15 downto 0);  -- ETHERTYPE_FIELD
    probe7      : in std_logic_vector(159 downto 0); -- IP_HEADER_FIELD
    probe8      : in std_logic_vector(63 downto 0);  -- UDP_HEADER_FIELD
    probe9      : in std_logic_vector(7 downto 0);   -- IP_PROTOCOL_HEADER
    probe10     : in std_logic_vector(31 downto 0);  -- IP_SOURCE_ADDR
    probe11     : in std_logic_vector(31 downto 0);  -- IP_DEST_ADDR
    probe12     : in std_logic_vector(15 downto 0);  -- IP_IDENTIFICATION
    probe13     : in std_logic_vector(7 downto 0);   -- IP_VERSION
    probe14     : in std_logic_vector(15 downto 0);  -- IP_HEADER_CHECKSUM
    probe15     : in std_logic_vector(15 downto 0);  -- UDP_SOURCE_PORT
    probe16     : in std_logic_vector(15 downto 0);  -- UDP_DEST_PORT
    probe17     : in std_logic_vector(15 downto 0);  -- UDP_LENGTH
    probe18     : in std_logic   -- HEADERS_PARSED
);
end component ila_parser_headers;



begin

ila_headers: ila_parser_headers
port map (
    clk                 => CLK,
    probe0              => udp_identificator,
    probe1              => S_AXIS_TVALID,
    probe2              => arp_request_flag,
    probe3              => arp_reply_flag  ,
    probe4              => da_reg,
    probe5              => sa_reg,
    probe6              => ethertype_reg,
    probe7              => ip_header_reg,
    probe8              => udp_header_reg,
    probe9              => ip_protocol_reg,
    probe10             => ip_source_addr_reg,
    probe11             => ip_dest_addr_reg,
    probe12             => ip_identification_reg,
    probe13             => ip_version_reg,
    probe14             => ip_header_checksum_reg,
    probe15             => udp_source_port_reg,
    probe16             => udp_dest_port_reg,
    probe17             => udp_length_reg,
    probe18             => headers_parsed_valid
);

 -- Output assignments
    DA_FIELD            <= da_reg                   ;
    SA_FIELD            <= sa_reg                   ;
    ETHERTYPE_FIELD     <= ethertype_reg            ;
    IP_HEADER_FIELD     <= ip_header_reg            ;
    UDP_HEADER_FIELD    <= udp_header_reg           ;
    IS_UDP_PACKET       <= udp_identificator        ;
    IS_ARP_PACKET       <= arp_ident                ;
    ARP_REQUEST         <= arp_request_flag         ;
    ARP_REPLY           <= arp_reply_flag           ;
    IP_PROTOCOL_HEADER  <= ip_protocol_reg          ;
    
    IP_SOURCE_ADDR      <= ip_source_addr_reg       ;
    IP_DEST_ADDR        <= ip_dest_addr_reg         ;
    IP_IDENTIFICATION   <= ip_identification_reg    ;
    IP_VERSION          <= ip_version_reg           ;
    IP_HEADER_CHECKSUM  <= ip_header_checksum_reg   ;
    
    UDP_SOURCE_PORT     <= udp_source_port_reg      ;
    UDP_DEST_PORT       <= udp_dest_port_reg        ;
    UDP_LENGTH          <= udp_length_reg           ;

    ARP_HTYPE_FIELD     <= arp_htype_reg            ;
    ARP_PTYPE_FIELD     <= arp_ptype_reg            ;
    ARP_HLEN_FIELD      <= arp_hlen_reg             ;
    ARP_PLEN_FIELD      <= arp_plen_reg             ;
    ARP_OPERATION_FIELD <= arp_operation_reg        ;
    ARP_SHA_FIELD       <= arp_sha_reg              ;
    ARP_SPA_FIELD       <= arp_spa_reg              ;
    ARP_THA_FIELD       <= arp_tha_reg              ;
    ARP_TPA_FIELD       <= arp_tpa_reg              ;

    HEADERS_PARSED      <= headers_parsed_valid     ;

    -- Stage 0: Input registration
    process(CLK)
    begin
        if rising_edge(CLK) then

                s0_tdata    <= S_AXIS_TDATA     ;
                s0_tkeep    <= S_AXIS_TKEEP     ;
                s0_tvalid   <= S_AXIS_TVALID    ;
                s0_tlast    <= S_AXIS_TLAST     ;
            end if;
    end process;

    -- Stage 1: Analyze all TKEEP blocks to find first valid byte
    gen_analyze_blocks: for i in 0 to ANALYZE_BLOCKS-1 generate
        s1_tkeep_blocks(i) <= s0_tkeep(SKIP_BLOCKS*4 + i*4 + 3 downto SKIP_BLOCKS*4 + i*4);
    end generate;
    
    process(CLK)
        variable v_coarse : integer range 0 to (DW_DATA*8)-1;
        variable v_fine   : std_logic_vector(3 downto 0);
        variable v_found  : boolean;
    begin
        if rising_edge(CLK) then

                v_coarse := 0;
                v_fine   := "1111"; -- default if all blocks zero (should not happen)
                v_found  := false;
                
                for i in 0 to ANALYZE_BLOCKS-1 loop
                    if (s1_tkeep_blocks(i) /= "0000") and not v_found then
                        v_coarse := (SKIP_BLOCKS + i) * 4;
                        v_fine   := s1_tkeep_blocks(i);
                        v_found  := true;
                    end if;
                end loop;
                
                s1_coarse_shift_val <= v_coarse;
                s1_fine_win         <= v_fine;
                s1_tvalid           <= s0_tvalid;
                s1_tlast            <= s0_tlast;
                s1_tdata_shifted    <= s0_tdata;
            end if;
    end process;

    -- Stage 2: Fine alignment
    process(CLK)
    begin
        if rising_edge(CLK) then

                s2_tvalid           <= s1_tvalid;  
                s2_tlast            <= s1_tlast;
                s2_tdata_coarse     <= s1_tdata_shifted;
                
                -- Find first '1' in fine window
                if (s1_fine_win(0) = '1') then
                    s2_fine_shift_val <= 0;
                elsif (s1_fine_win(1) = '1') then
                    s2_fine_shift_val <= 1;
                elsif (s1_fine_win(2) = '1') then
                    s2_fine_shift_val <= 2;
                elsif (s1_fine_win(3) = '1') then
                    s2_fine_shift_val <= 3;
                else
                    s2_fine_shift_val <= 0;
                end if;
                
                s2_total_shift_val <= s1_coarse_shift_val + s2_fine_shift_val;
            end if;
    end process;

    -- Stage 3: Final alignment (left shift to align data to LSBs)
    process(CLK)
        variable shifted_data : std_logic_vector((DW_DATA*8)-1 downto 0);
    begin
        if rising_edge(CLK) then
                s3_tvalid           <= s2_tvalid;
                s3_tlast            <= s2_tlast;
                s3_total_shift_bits <= s2_total_shift_val;

                -- Left shift: place valid data starting at LSB, zero out higher bits
                shifted_data := (others => '0');
                shifted_data((DW_DATA*8)-1 - s2_total_shift_val downto 0) := 
                    s2_tdata_coarse((DW_DATA*8)-1 downto s2_total_shift_val);
                s3_tdata_aligned <= shifted_data;
            end if;
    end process;

    -- Stage 4: Header accumulation 
    gen_512byte_accum: if DW_DATA = 512 generate
        process(CLK)
        begin
            if rising_edge(CLK) then
                if RESET = '1' then
                    header_buffer <= (others => '0');
                    bit_cnt <= 0;
                    flag_data <= '0';
                else
                    if (s3_tvalid = '1') then
                        header_buffer <= s3_tdata_aligned;
                        bit_cnt <= BIT_WIDTH;
                        
                        if (BIT_WIDTH >= TOTAL_BITS) then
                            flag_data <= '1';
                        end if;
                    end if;
                end if;
            end if;
        end process;
    end generate;

    -- Stage 4: Header accumulation for narrower buses (DW_DATA < 512)
gen_normal_accum: if DW_DATA < 512 generate
    process(CLK)
        variable v_new_bit_cnt : integer range 0 to MAX_WIDTH;
    begin
        if rising_edge(CLK) then
            if RESET = '1' then
                header_buffer <= (others => '0');
                bit_cnt <= 0;
                flag_data <= '0';
            else
                if (s3_tlast = '1' and s3_tvalid = '1') then
                    flag_data <= '0';
                end if;
                
                if (s3_tvalid = '1') then
                    if (bit_cnt = 0) or (s3_tlast = '1' and flag_data = '1') then
                        if (s3_tlast = '1' and flag_data = '1') then
                            bit_cnt <= 0;
                            v_new_bit_cnt := BIT_WIDTH - s3_total_shift_bits;
                        else
                            v_new_bit_cnt := BIT_WIDTH - s3_total_shift_bits;
                        end if;
                        
                        header_buffer(v_new_bit_cnt-1 downto 0) <= 
                            s3_tdata_aligned(BIT_WIDTH-1 downto s3_total_shift_bits);
                    else
                        v_new_bit_cnt := bit_cnt + BIT_WIDTH;
                        if (v_new_bit_cnt <= MAX_WIDTH) then
                            header_buffer(bit_cnt + BIT_WIDTH - 1 downto bit_cnt) <= s3_tdata_aligned;
                        else
                            v_new_bit_cnt := bit_cnt; 
                        end if;
                    end if;
                    
                    bit_cnt <= v_new_bit_cnt;
                    
                    if (flag_data = '0') and 
                       ((bit_cnt = 0 and (BIT_WIDTH - s3_total_shift_bits) >= TOTAL_BITS) or
                        (v_new_bit_cnt >= TOTAL_BITS)) then
                        flag_data <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;
end generate;

    -- Header extraction process
    process(CLK)
    begin
        if rising_edge(CLK) then
           
                -- Ethernet header fields
                da_reg                  <= header_buffer(ETH_DST_MAC_HIGH downto ETH_DST_MAC_LOW);
                sa_reg                  <= header_buffer(ETH_SRC_MAC_HIGH downto ETH_SRC_MAC_LOW);
                ethertype_reg           <= header_buffer(ETH_TYPE_HIGH downto ETH_TYPE_LOW);
                
                -- ARP header fields
                arp_htype_reg           <= header_buffer(ARP_HTYPE_HIGH downto ARP_HTYPE_LOW);
                arp_ptype_reg           <= header_buffer(ARP_PTYPE_HIGH downto ARP_PTYPE_LOW);
                arp_hlen_reg            <= header_buffer(ARP_HLEN_HIGH downto ARP_HLEN_LOW);
                arp_plen_reg            <= header_buffer(ARP_PLEN_HIGH downto ARP_PLEN_LOW);
                arp_operation_reg       <= header_buffer(ARP_OPER_HIGH downto ARP_OPER_LOW);
                arp_sha_reg             <= header_buffer(ARP_SHA_HIGH downto ARP_SHA_LOW);
                arp_spa_reg             <= header_buffer(ARP_SPA_HIGH downto ARP_SPA_LOW);
                arp_tha_reg             <= header_buffer(ARP_THA_HIGH downto ARP_THA_LOW);
                arp_tpa_reg             <= header_buffer(ARP_TPA_HIGH downto ARP_TPA_LOW);
                
                -- IP header fields
                ip_header_reg           <= header_buffer(IP_DST_ADDR_HIGH downto IP_VER_IHL_LOW);
                ip_source_addr_reg      <= header_buffer(IP_SRC_ADDR_HIGH downto IP_SRC_ADDR_LOW);
                ip_dest_addr_reg        <= header_buffer(IP_DST_ADDR_HIGH downto IP_DST_ADDR_LOW);
                ip_identification_reg   <= header_buffer(IP_ID_HIGH downto IP_ID_LOW);
                ip_version_reg          <= header_buffer(IP_VER_IHL_HIGH downto IP_VER_IHL_LOW);
                ip_header_checksum_reg  <= header_buffer(IP_CHECKSUM_HIGH downto IP_CHECKSUM_LOW);
                
                -- UDP header fields 
                udp_header_reg          <= header_buffer(UDP_CHECKSUM_HIGH downto UDP_SRC_PORT_LOW);
                udp_source_port_reg     <= header_buffer(UDP_SRC_PORT_HIGH downto UDP_SRC_PORT_LOW);
                udp_dest_port_reg       <= header_buffer(UDP_DST_PORT_HIGH downto UDP_DST_PORT_LOW);
                udp_length_reg          <= header_buffer(UDP_LEN_HIGH downto UDP_LEN_LOW);
                
                -- Protocol field
                ip_protocol_reg         <= header_buffer(IP_PROTO_HIGH downto IP_PROTO_LOW);
                
                -- ARP packet detection
                if (header_buffer(ETH_TYPE_HIGH downto ETH_TYPE_LOW) = ARP_TYPE) then
                    arp_ident <= '1';
                else
                    arp_ident <= '0';
                end if;
                
                -- ARP operation detection
                if (header_buffer(ARP_OPER_HIGH downto ARP_OPER_LOW) = ARP_REQUEST_OP and 
                    header_buffer(ETH_TYPE_HIGH downto ETH_TYPE_LOW) = ARP_TYPE) then
                    arp_request_flag <= '1';
                else
                    arp_request_flag <= '0';
                end if;
                
                if (header_buffer(ARP_OPER_HIGH downto ARP_OPER_LOW) = ARP_REPLY_OP and 
                    header_buffer(ETH_TYPE_HIGH downto ETH_TYPE_LOW) = ARP_TYPE) then
                    arp_reply_flag <= '1';
                else
                    arp_reply_flag <= '0';
                end if;
               
                -- UDP packet detection
                if (header_buffer(IP_PROTO_HIGH downto IP_PROTO_LOW) = UDP_PROTOCOL)  then
                    udp_identificator <= '1';
                else
                    udp_identificator <= '0';
                end if;
                
                headers_parsed_valid <= flag_data;
            end if;
    end process;


end eth_header_parser_arch;
