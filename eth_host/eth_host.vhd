library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_host is
    generic (
        DW_DATA : integer := 64;
        FLAG_OUT : boolean := True
    );
    port (
        CLK                     : in std_logic;
        RESET_N                 : in std_logic;
        S_AXIS_TVALID           : in std_logic;
        S_AXIS_TREADY           : out std_logic;
        S_AXIS_TDATA            : in std_logic_vector((DW_DATA*8)-1 downto 0);
        S_AXIS_TKEEP            : in std_logic_vector(DW_DATA-1 downto 0);
        S_AXIS_TLAST            : in std_logic;
        M_AXIS_TDATA            : out std_logic_vector((DW_DATA*8)-1 downto 0);
        M_AXIS_TKEEP            : out std_logic_vector(DW_DATA-1 downto 0);
        M_AXIS_TVALID           : out std_logic;
        M_AXIS_TLAST            : out std_logic;
        M_AXIS_TREADY           : in std_logic;
        M_AXIS_TDEST            : out std_logic_vector(7 downto 0);
        M_AXIS_TUSER            : out std_logic_vector(7 downto 0);
        S_AXI_AWADDR            : in std_logic_vector(9 downto 0);
        S_AXI_AWVALID           : in std_logic;
        S_AXI_AWREADY           : out std_logic;
        S_AXI_WDATA             : in std_logic_vector(31 downto 0);
        S_AXI_WSTRB             : in std_logic_vector(3 downto 0);
        S_AXI_WVALID            : in std_logic;
        S_AXI_WREADY            : out std_logic;
        S_AXI_BRESP             : out std_logic_vector(1 downto 0);
        S_AXI_BVALID            : out std_logic;
        S_AXI_BREADY            : in std_logic;
        S_AXI_ARADDR            : in std_logic_vector(9 downto 0);
        S_AXI_ARVALID           : in std_logic;
        S_AXI_ARREADY           : out std_logic;
        S_AXI_RDATA             : out std_logic_vector(31 downto 0);
        S_AXI_RRESP             : out std_logic_vector(1 downto 0);
        S_AXI_RVALID            : out std_logic;
        S_AXI_RREADY            : in std_logic;
        IS_UDP_PACKET_OUT       : out std_logic;
        CRC_VALID               : out std_logic;
        PACKET_FIELDS_VALID_OUT : out std_logic;
        PACKET_PROCESSED_OUT    : out std_logic; 
        ARP_RESPONSE_SENT       : out std_logic
    );
end entity eth_host;

architecture eth_host_arch of eth_host is

    signal crc_check : std_logic; 

    signal reset_parser_int          : std_logic;
    signal is_udp_packet_int         : std_logic;
    signal is_arp_packet_int         : std_logic;
    signal arp_request_int           : std_logic;
    signal arp_reply_int             : std_logic;
    signal da_field_int              : std_logic_vector(47 downto 0);
    signal sa_field_int              : std_logic_vector(47 downto 0);
    signal ethertype_field_int       : std_logic_vector(15 downto 0);
    signal ip_header_field_int       : std_logic_vector(159 downto 0);
    signal udp_header_field_int      : std_logic_vector(63 downto 0);
    signal m_axis_hdr_tvalid_int     : std_logic;
    signal m_axis_hdr_tready_int     : std_logic;
    signal m_axis_hdr_tdata_int      : std_logic_vector(335 downto 0);
    signal m_axis_hdr_tlast_int      : std_logic;
    signal reset_signal_int          : std_logic;
    signal s_axis_hdr_tvalid_int     : std_logic;
    signal s_axis_hdr_tready_int     : std_logic;
    signal s_axis_hdr_tdata_int      : std_logic_vector(335 downto 0);
    signal s_axis_hdr_tlast_int      : std_logic;
    signal packet_processed_2_int    : std_logic;
    signal m_axis_tlast_internal_int : std_logic;
    signal m_ready_int               : std_logic;
    signal packet_fields_valid_int   : std_logic;
    signal packet_processed_int      : std_logic;
    signal da_field_reg_int          : std_logic_vector(47 downto 0);
    signal sa_field_reg_int          : std_logic_vector(47 downto 0);
    signal ethertype_field_reg_int   : std_logic_vector(15 downto 0);
    signal ip_source_addr_int        : std_logic_vector(31 downto 0);
    signal ip_dest_addr_int          : std_logic_vector(31 downto 0);
    signal ip_protocol_int           : std_logic_vector(7 downto 0);
    signal ip_identification_int     : std_logic_vector(15 downto 0);
    signal ip_version_int            : std_logic_vector(7 downto 0);
    signal ip_header_checksum_int    : std_logic_vector(15 downto 0);
    signal udp_source_port_int       : std_logic_vector(15 downto 0);
    signal udp_dest_port_int         : std_logic_vector(15 downto 0);
    signal udp_length_int            : std_logic_vector(15 downto 0);
    signal udp_signal_table_int      : std_logic;
    signal reset_parser_active_high  : std_logic;
    signal m_axis_tlast_sig          : std_logic;
    signal s_axis_tready_sig         : std_logic;
    signal packet_active             : std_logic;
    signal packet_start              : std_logic;
    signal packet_end_detected       : std_logic;
    signal valid_packet              : std_logic;
    signal headers_parsed            : std_logic;
    signal s_axis_tready_internal    : std_logic;
    signal m_axis_tdata_internal     : std_logic_vector((DW_DATA*8)-1 downto 0);
    signal m_axis_tkeep_internal     : std_logic_vector(DW_DATA-1 downto 0);
    signal m_axis_tvalid_internal    : std_logic;
    signal m_axis_tlast_internal     : std_logic;
    signal m_axis_tdest_internal     : std_logic_vector(7 downto 0);
    signal IP_PROTOCOL_HEADER_reg    : std_logic_vector(7 downto 0);
    signal crc_valid_int             : std_logic;
    
    signal arp_htype_int             : std_logic_vector(15 downto 0);
    signal arp_ptype_int             : std_logic_vector(15 downto 0);
    signal arp_hlen_int              : std_logic_vector(7 downto 0);
    signal arp_plen_int              : std_logic_vector(7 downto 0);
    signal arp_operation_int         : std_logic_vector(15 downto 0);
    signal arp_sha_int               : std_logic_vector(47 downto 0);
    signal arp_spa_int               : std_logic_vector(31 downto 0);
    signal arp_tha_int               : std_logic_vector(47 downto 0);
    signal arp_tpa_int               : std_logic_vector(31 downto 0);
    
    signal arp_response_tdata        : std_logic_vector((DW_DATA*8)-1 downto 0);
    signal arp_response_tkeep        : std_logic_vector(DW_DATA-1 downto 0);
    signal arp_response_tvalid       : std_logic;
    signal arp_response_tlast        : std_logic;
    signal arp_response_sent_int     : std_logic;
    signal arp_pending               : std_logic;
    
    signal flag_out_active           : std_logic;
    signal m_axis_tdata_flag_out     : std_logic_vector((DW_DATA*8)-1 downto 0);
    signal m_axis_tkeep_flag_out     : std_logic_vector(DW_DATA-1 downto 0);
    signal m_axis_tvalid_flag_out    : std_logic;
    signal m_axis_tlast_flag_out     : std_logic;
    
begin

    flag_out_active <= '1' when FLAG_OUT else '0';
    
    m_axis_tdata_flag_out <= S_AXIS_TDATA;
    m_axis_tkeep_flag_out <= S_AXIS_TKEEP;
    m_axis_tvalid_flag_out <= S_AXIS_TVALID and flag_out_active;
    m_axis_tlast_flag_out <= S_AXIS_TLAST;

    reset_parser_active_high <= not RESET_N;
    reset_signal_int <= not RESET_N;
    s_axis_hdr_tvalid_int <= m_axis_hdr_tvalid_int;
    s_axis_hdr_tdata_int <= m_axis_hdr_tdata_int;
    s_axis_hdr_tlast_int <= m_axis_hdr_tlast_int;
    m_axis_hdr_tready_int <= s_axis_hdr_tready_int;
    udp_signal_table_int <= is_udp_packet_int;
    packet_processed_2_int <= packet_processed_int;
    m_axis_tlast_internal_int <= m_axis_tlast_sig;
    m_ready_int <= M_AXIS_TREADY;
    S_AXIS_TREADY <= s_axis_tready_internal;
    IS_UDP_PACKET_OUT <= is_udp_packet_int;
    PACKET_FIELDS_VALID_OUT <= packet_fields_valid_int;
    PACKET_PROCESSED_OUT <= packet_processed_int;
    s_axis_tready_sig <= s_axis_tready_internal;
    m_axis_tlast_sig <= m_axis_tlast_internal;
    s_axis_tready_internal <= '1';
    packet_active <= '1';
    ARP_RESPONSE_SENT <= arp_response_sent_int;

    eth_header_parser_inst : entity work.eth_header_parser
        generic map (
            DW_DATA => DW_DATA
        )
        port map (
            CLK                 => CLK,
            RESET               => reset_parser_active_high,
            S_AXIS_TVALID       => S_AXIS_TVALID,
            S_AXIS_TREADY       => s_axis_tready_sig,
            S_AXIS_TDATA        => S_AXIS_TDATA,
            S_AXIS_TKEEP        => S_AXIS_TKEEP,
            S_AXIS_TLAST        => S_AXIS_TLAST,
            IS_UDP_PACKET       => is_udp_packet_int,
            IS_ARP_PACKET       => is_arp_packet_int,
            ARP_REQUEST         => arp_request_int, 
            ARP_REPLY           => arp_reply_int,
            DA_FIELD            => da_field_int,
            SA_FIELD            => sa_field_int,
            ETHERTYPE_FIELD     => ethertype_field_int,
            IP_HEADER_FIELD     => ip_header_field_int,
            IP_PROTOCOL_HEADER  => IP_PROTOCOL_HEADER_reg,
            UDP_HEADER_FIELD    => udp_header_field_int,
            IP_SOURCE_ADDR      => ip_source_addr_int,
            IP_DEST_ADDR        => ip_dest_addr_int,
            IP_IDENTIFICATION   => ip_identification_int,
            IP_VERSION          => ip_version_int,
            IP_HEADER_CHECKSUM  => ip_header_checksum_int,
            UDP_SOURCE_PORT     => udp_source_port_int,
            UDP_DEST_PORT       => udp_dest_port_int,
            UDP_LENGTH          => udp_length_int,
            ARP_HTYPE_FIELD     => arp_htype_int,
            ARP_PTYPE_FIELD     => arp_ptype_int,
            ARP_HLEN_FIELD      => arp_hlen_int,
            ARP_PLEN_FIELD      => arp_plen_int,
            ARP_OPERATION_FIELD => arp_operation_int,
            ARP_SHA_FIELD       => arp_sha_int,
            ARP_SPA_FIELD       => arp_spa_int,
            ARP_THA_FIELD       => arp_tha_int,
            ARP_TPA_FIELD       => arp_tpa_int,
            HEADERS_PARSED      => headers_parsed
        );

    eth_route_table_inst : entity work.eth_route_table
        generic map (
            TABLE_SIZE => 5,
            DW_DATA    => DW_DATA
        )
        port map (
            CLK                    => CLK,
            RESET                  => RESET_N,
            DESTINATION_MAC        => da_field_int,
            SOURCE_MAC             => sa_field_int,
            ETHER_TYPE             => ethertype_field_int,
            IP_VERSION             => ip_version_int,
            IP_PROTOCOL            => IP_PROTOCOL_HEADER_reg,
            IP_SOURCE_ADDR         => ip_source_addr_int,
            IP_DEST_ADDR           => ip_dest_addr_int,
            UDP_SOURCE_PORT        => udp_source_port_int,
            UDP_DEST_PORT          => udp_dest_port_int,
            UDP_SIGNAL_TABLE       => is_udp_packet_int,
            PACKET_FIELDS_VALID    => packet_fields_valid_int,
            CRC_VALID_IN           => crc_valid_int,
            S_AXIS_TDATA           => S_AXIS_TDATA,
            S_AXIS_TKEEP           => S_AXIS_TKEEP,
            S_AXIS_TVALID          => S_AXIS_TVALID,
            S_AXIS_TLAST           => S_AXIS_TLAST,
            S_AXIS_TREADY          => open,
            M_AXIS_TREADY          => M_AXIS_TREADY,
            M_AXIS_TDATA           => m_axis_tdata_internal,
            M_AXIS_TKEEP           => m_axis_tkeep_internal,
            M_AXIS_TVALID          => m_axis_tvalid_internal,
            M_AXIS_TLAST           => m_axis_tlast_internal,
            M_AXIS_TDEST           => m_axis_tdest_internal,
            M_AXIS_TUSER           => M_AXIS_TUSER,
            S_AXI_AWADDR           => S_AXI_AWADDR,
            S_AXI_AWVALID          => S_AXI_AWVALID,
            S_AXI_AWREADY          => S_AXI_AWREADY,
            S_AXI_WDATA            => S_AXI_WDATA,
            S_AXI_WSTRB            => S_AXI_WSTRB,
            S_AXI_WVALID           => S_AXI_WVALID,
            S_AXI_WREADY           => S_AXI_WREADY,
            S_AXI_BRESP            => S_AXI_BRESP,
            S_AXI_BVALID           => S_AXI_BVALID,
            S_AXI_BREADY           => S_AXI_BREADY,
            S_AXI_ARADDR           => S_AXI_ARADDR,
            S_AXI_ARVALID          => S_AXI_ARVALID,
            S_AXI_ARREADY          => S_AXI_ARREADY,
            S_AXI_RDATA            => S_AXI_RDATA,
            S_AXI_RRESP            => S_AXI_RRESP,
            S_AXI_RVALID           => S_AXI_RVALID,
            S_AXI_RREADY           => S_AXI_RREADY
        );
        
    process(CLK, RESET_N)
    begin
        if RESET_N = '0' then
            M_AXIS_TDATA <= (others => '0');
            M_AXIS_TKEEP <= (others => '0');
            M_AXIS_TVALID <= '0';
            M_AXIS_TLAST <= '0';
            M_AXIS_TDEST <= (others => '0');
        elsif rising_edge(CLK) then
            if flag_out_active = '1' then
                M_AXIS_TDATA <= m_axis_tdata_flag_out;
                M_AXIS_TKEEP <= m_axis_tkeep_flag_out;
                M_AXIS_TVALID <= m_axis_tvalid_flag_out;
                M_AXIS_TLAST <= m_axis_tlast_flag_out;
                M_AXIS_TDEST <= (others => '0');
            else
                M_AXIS_TDATA <= m_axis_tdata_internal;
                M_AXIS_TKEEP <= m_axis_tkeep_internal;
                M_AXIS_TVALID <= m_axis_tvalid_internal;
                M_AXIS_TLAST <= m_axis_tlast_internal;
                M_AXIS_TDEST <= m_axis_tdest_internal;
            end if;
        end if;
    end process;

packet_fields_valid_int <= headers_parsed;

end architecture eth_host_arch;