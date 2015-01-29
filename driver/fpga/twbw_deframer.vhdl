------------------------------------------------------------------------
-- TWBW Deframer - DAC sample deframer with time and burst controls
--
-- Copyright (c) 2015-2015 Lime Microsystems
-- Copyright (c) 2015-2015 Andrew "bunnie" Huang
-- SPDX-License-Identifier: Apache-2.0
-- http://www.apache.org/licenses/LICENSE-2.0
------------------------------------------------------------------------

library work;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity twbw_deframer is
    generic(
        -- the size of the input fifo containing the framed data
        -- either use a small number and provide external buffering
        -- or set this to a reasonable size for your application
        FIFO_DEPTH : positive := 1024;

        -- the depth of the status fifo
        STAT_DEPTH : positive := 16
    );
    port(
        -- The DAC clock domain used for all interfaces.
        clk : in std_logic;

        -- synchronous reset
        rst : in std_logic;

        -- The current time in clock ticks.
        in_time : in unsigned;

        -- The output DAC interface:
        -- There is no valid signal, a ready signal with no data => underflow.
        -- To allow for frame overhead, this bus cannot be ready every cycle.
        -- Many interfaces do not consume transmit data at every clock cycle.
        -- If this is not the case, we recommend doubling the DAC data width.
        dac_tdata : out std_logic_vector;
        dac_tready : in std_logic;

        -- Input stream interface:
        -- The tuser signal indicates metadata and not sample data
        in_tdata : in std_logic_vector;
        in_tuser : in std_logic_vector(0 downto 0);
        in_tlast : in std_logic;
        in_tvalid : in std_logic;
        in_tready : out std_logic;

        -- status bus interface
        stat_tdata : out std_logic_vector(31 downto 0);
        stat_tlast : out std_logic;
        stat_tvalid : out std_logic;
        stat_tready : in std_logic;

        -- Transmit activity indicator based on internal state.
        -- Example: use this signal to drive external switches and LEDs.
        dac_active : out boolean
    );
end entity twbw_deframer;

architecture rtl of twbw_deframer is

    constant DATA_WIDTH : positive := dac_tdata'length;
    constant TIME_WIDTH : positive := in_time'length;

    -- state machine inspects the DAC from these signals
    signal dac_fifo_out_valid : std_logic;
    signal dac_fifo_in_data : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal dac_fifo_in_valid : std_logic;
    signal dac_fifo_in_ready : std_logic;

    -- state machine drives the status messages with these signals
    signal stat_fifo_in_data : std_logic_vector(127 downto 0);
    signal stat_fifo_in_valid : std_logic;
    signal stat_fifo_in_ready : std_logic;

    -- state machine controls the outgoing framed bus signals
    signal framed_fifo_in_full : std_logic_vector(2+DATA_WIDTH-1 downto 0);
    signal framed_fifo_out_full : std_logic_vector(2+DATA_WIDTH-1 downto 0);
    signal framed_fifo_out_data : std_logic_vector(DATA_WIDTH-1 downto 0);
    signal framed_fifo_out_user : std_logic_vector(0 downto 0);
    signal framed_fifo_out_last : std_logic;
    signal framed_fifo_out_valid : std_logic;
    signal framed_fifo_out_ready : std_logic;

    -- internal dac active indicator
    signal dac_active_i : boolean;

    -- state machine enumerations
    type state_type is (
        STATE_HDR0_IN,
        STATE_HDR1_IN,
        STATE_HDR2_IN,
        STATE_HDR3_IN,
        STATE_SAMPS_IN,
        STATE_STAT_OUT);
    signal state : state_type;

begin
    assert (TIME_WIDTH <= 64) report "twbw_deframer: time width too large" severity failure;
    assert (DATA_WIDTH >= 32) report "twbw_deframer: data width too small" severity failure;

    --boolean condition tracking
    dac_active <= dac_active_i;

    --------------------------------------------------------------------
    -- short fifo between dac in and state machine
    -- this fifo ensures a continuous streaming despite deframing overhead
    --------------------------------------------------------------------
    dac_fifo: entity work.StreamFifo
    generic map (
        --configure a small distributed ram
        MEM_SIZE => 16, --must be greater than the number of header and wait states
        SYNC_READ => false
    )
    port map (
        clk => clk,
        rst => rst,
        in_data => dac_fifo_in_data,
        in_valid => dac_fifo_in_valid,
        in_ready => dac_fifo_in_ready,
        out_data => dac_tdata,
        out_valid => dac_fifo_out_valid,
        out_ready => dac_tready
    );

    --------------------------------------------------------------------
    -- short fifo between state machine and stat bus
    -- this fifo changes size and gives storage space
    --------------------------------------------------------------------
    stat_fifo: entity work.stat_msg_fifo128
    generic map (
        MEM_SIZE => STAT_DEPTH
    )
    port map (
        clk => clk,
        rst => rst,
        in_tdata => stat_fifo_in_data,
        in_tvalid => stat_fifo_in_valid,
        in_tready => stat_fifo_in_ready,
        out_tdata => stat_tdata,
        out_tlast => stat_tlast,
        out_tvalid => stat_tvalid,
        out_tready => stat_tready
    );

    --------------------------------------------------------------------
    -- fifo between input stream and state machine
    --------------------------------------------------------------------
    framed_fifo : entity work.StreamFifo
    generic map (
        MEM_SIZE => FIFO_DEPTH,
        SYNC_READ => FIFO_DEPTH > 16
    )
    port map (
        clk => clk,
        rst => rst,
        in_data => framed_fifo_in_full,
        in_valid => in_tvalid,
        in_ready => in_tready,
        out_data => framed_fifo_out_full,
        out_valid => framed_fifo_out_valid,
        out_ready => framed_fifo_out_ready
    );

    framed_fifo_out_data <= framed_fifo_out_full(DATA_WIDTH-1 downto 0);
    framed_fifo_out_last <= framed_fifo_out_full(DATA_WIDTH);
    framed_fifo_out_user <= framed_fifo_out_full(DATA_WIDTH+1 downto DATA_WIDTH+1);

    framed_fifo_in_full(DATA_WIDTH-1 downto 0) <= in_tdata;
    framed_fifo_in_full(DATA_WIDTH) <= in_tlast;
    framed_fifo_in_full(DATA_WIDTH+1 downto DATA_WIDTH+1) <= in_tuser;

    --------------------------------------------------------------------
    -- deframer state machine
    --------------------------------------------------------------------
    process (clk) begin

    if (rising_edge(clk)) then
        if (rst = '1') then
            dac_active_i <= false;
            state <= STATE_HDR0_IN;
        else case state is

        when STATE_HDR0_IN =>
        when STATE_HDR1_IN =>
        when STATE_HDR2_IN =>
        when STATE_HDR3_IN =>
        when STATE_SAMPS_IN =>
        when STATE_STAT_OUT =>

        end case;
        end if;
    end if;

    end process;


end architecture rtl;
