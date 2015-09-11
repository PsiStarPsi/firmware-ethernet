---------------------------------------------------------------------------------
-- Title         : ARP Packet TX
-- Project       : General Purpose Core
---------------------------------------------------------------------------------
-- File          : ArpPacketTx.vhd
-- Author        : Kurtis Nishimura
---------------------------------------------------------------------------------
-- Description:
-- Connects to Ethernet layer, sends ARP packets
---------------------------------------------------------------------------------

LIBRARY ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use work.UtilityPkg.all;
use work.GigabitEthPkg.all;

entity ArpPacketTx is 
   generic (
      GATE_DELAY_G : time := 1 ns
   );
   port ( 
      -- 125 MHz ethernet clock in
      ethTxClk          : in  sl;
      ethTxRst          : in  sl := '0';
      -- Data to send
      arpSenderMac      : in  MacAddrType;
      arpSenderIp       : in  IpAddrType;
      arpTargetMac      : in  MacAddrType;
      arpTargetIp       : in  IpAddrType;
      arpOp             : in  slv(15 downto 0);
      arpReq            : in  sl;
      arpAck            : out sl;
      -- User data to be sent
      ethTxData         : out slv(7 downto 0);
      ethTxDataValid    : out sl;
      ethTxDataLastByte : out sl;
      ethTxDataReady    : in  sl
   ); 
end ArpPacketTx;

architecture rtl of ArpPacketTx is

   type StateType is (IDLE_S, 
                      HTYPE_S, PTYPE_S, HLEN_S, PLEN_S, OPER_S, 
                      SHA_S, SPA_S, THA_S, TPA_S, WAIT_S);
   
   type RegType is record
      state        : StateType;
      wrCount      : slv(2 downto 0);
      senderMac    : MacAddrType;
      senderIp     : IpAddrType;
      targetMac    : MacAddrType;
      targetIp     : IpAddrType;
      last         : sl;
      op           : slv(15 downto 0);
      ack          : sl;
   end record RegType;
   
   constant REG_INIT_C : RegType := (
      state        => IDLE_S,
      wrCount      => (others => '0'),
      senderMac    => MAC_ADDR_INIT_C,
      senderIp     => IP_ADDR_INIT_C,
      targetMac    => MAC_ADDR_INIT_C,
      targetIp     => IP_ADDR_INIT_C,
      last         => '0',
      op           => (others => '0'),
      ack          => '0'
   );
   
   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;
   
   -- ISE attributes to keep signals for debugging
   -- attribute keep : string;
   -- attribute keep of r : signal is "true";
   -- attribute keep of crcOut : signal is "true";      
   
   -- Vivado attributes to keep signals for debugging
   -- attribute dont_touch : string;
   -- attribute dont_touch of r : signal is "true";
   -- attribute dont_touch of crcOut : signal is "true";   
   
begin

   comb : process(r,arpSenderMac,arpSenderIp,arpTargetMac,arpTargetIp,
                  arpOp,arpReq,ethTxDataReady,ethTxRst) is
      variable v : RegType;
   begin
      v := r;

      -- Set defaults / reset any pulsed signals
      v.ack             := '0';
      ethTxData         <= (others => '0');
      ethTxDataLastByte <= '0';
      ethTxDataValid    <= '0';
      
      -- State machine
      case(r.state) is 
         when IDLE_S =>
            ethTxData         <= (others => '0');
            ethTxDataValid    <= '0';
            ethTxDataLastByte <= '0';
            v.wrCount         := (others => '0');
            if arpReq = '1' then
               -- Register all input MACs/IPs
               v.senderMac := arpSenderMac;
               v.senderIp  := arpSenderIp;
               v.targetMac := arpTargetMac;
               v.targetIp  := arpTargetIp;
               v.op        := arpOp;
               v.state     := HTYPE_S;
            end if;
         when HTYPE_S =>
            ethTxData      <= getByte(1-conv_integer(r.wrCount),ARP_HTYPE_C);
            ethTxDataValid <= '1';
            if ethTxDataReady = '1' then
               v.wrCount := r.wrCount + 1;
               if (r.wrCount = 1) then
                  v.wrCount := (others => '0');
                  v.state   := PTYPE_S;
               end if;
            end if;
         when PTYPE_S =>
            ethTxData      <= getByte(1-conv_integer(r.wrCount),ARP_PTYPE_C);
            ethTxDataValid <= '1';
            if ethTxDataReady = '1' then
               v.wrCount := r.wrCount + 1;
               if (r.wrCount = 1) then
                  v.wrCount := (others => '0');
                  v.state   := HLEN_S;
               end if;
            end if;
         when HLEN_S =>
            ethTxData      <= ARP_HLEN_C;
            ethTxDataValid <= '1';
            if ethTxDataReady = '1' then
               v.state := PLEN_S;
            end if;
         when PLEN_S =>
            ethTxData      <= ARP_PLEN_C; 
            ethTxDataValid <= '1';
            if ethTxDataReady = '1' then
               v.state := OPER_S;
            end if;
         when OPER_S =>
            ethTxData      <= getByte(1-conv_integer(r.wrCount),r.op);
            ethTxDataValid <= '1';
            if ethTxDataReady = '1' then
               v.wrCount := r.wrCount + 1;
               if (r.wrCount = 1) then
                  v.wrCount := (others => '0');
                  v.state   := SHA_S;
               end if;
            end if;
         when SHA_S => 
            ethTxData      <= r.senderMac(5-conv_integer(r.wrCount));
            ethTxDataValid <= '1';
            if ethTxDataReady = '1' then
               v.wrCount := r.wrCount + 1;
               if (r.wrCount = 5) then
                  v.wrCount := (others => '0');
                  v.state   := SPA_S;
               end if;
            end if;
         when SPA_S =>
            ethTxData      <= r.senderIp(3-conv_integer(r.wrCount));
            ethTxDataValid <= '1';
            if ethTxDataReady = '1' then
               v.wrCount := r.wrCount + 1;
               if (r.wrCount = 3) then
                  v.wrCount := (others => '0');
                  v.state   := THA_S;
               end if;
            end if;
         when THA_S =>
            ethTxData      <= r.targetMac(5-conv_integer(r.wrCount));
            ethTxDataValid <= '1';
            if ethTxDataReady = '1' then
               v.wrCount := r.wrCount + 1;
               if (r.wrCount = 5) then
                  v.wrCount := (others => '0');
                  v.state   := TPA_S;
               end if;
            end if;
         when TPA_S =>
            ethTxData         <= r.targetIp(3-conv_integer(r.wrCount));
            ethTxDataValid    <= '1';
            if (r.wrCount = 3) then
               ethTxDataLastByte <= '1';
            end if;
            if ethTxDataReady = '1' then
               v.wrCount := r.wrCount + 1;
               if (r.wrCount = 3) then
                  v.wrCount := (others => '0');
                  v.state   := WAIT_S;
               end if;
            end if;
         when WAIT_S =>
            ethTxDataValid    <= '0';
            ethTxDataLastByte <= '0';
            v.ack := '1';
            if (arpReq = '0') then
               v.ack   := '0';
               v.state := IDLE_S;
            end if;
         when others =>
            v.state := IDLE_S;
      end case;
         
      -- Reset logic
      if (ethTxRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Outputs to ports
      arpAck <= r.ack;
      
      -- Assign variable to signal
      rin <= v;

   end process;

   seq : process (ethTxClk) is
   begin
      if (rising_edge(ethTxClk)) then
         r <= rin after GATE_DELAY_G;
      end if;
   end process seq;   

end rtl;
