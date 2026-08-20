# MTCP — planilha canônica (extração fiel do MTCP.zip, 19/08/2026)

Fonte: planilha do Gabriel Novalski. Extraída para texto porque o original é HTML
exportado e não se lê em diff. NÃO editar aqui — editar na planilha e reextrair.


## Documentation

```
 | A | B | C | D | E | F
1 | MTCPMarineTelematics Commanding Protocol.
2
3
4 | This document aims to describe a protocol intended to be used to interchange data and commandfor all the MarineTelematics devices connected in the MTNet, a CAN based proprietary network.
5
6
7 | Packet consists of:[IDENTIFIER, 29 bits extd CAN ID], [PARAM DATA, N bytes]All data in litle endian format.
8
9
10
11 | Revision History:15/10/24: Created initial version (Gabriel Novalski).22/09/25: Formatted the document and split in pages (Gabriel Novalski).16/10/25: Created CTR sensor status commands (Gabriel Novalski).23/10/25: Fixed inverted Neutral and Forward config positions in ECULAC, changed the Keep Alive. (Yuri)25/11/25: Fixed Neutral and Forward config positions in ECULAS. (Gabriel Novalski).1/12/25: Fixed the Neutral and Forward position in ECULAC.20/01/2026: Added support for options in ECULAC, main usage is for actuator overshoot. (Gabriel Novalski).18/02/2026: Added last error code and Voltage in value to CM02S. (Gabriel Novalski).26/02/2026: Added normailze calibration option in CTRPS. (Gabriel Novalski).20/07/2026: Added CM250 as a shared address alongside CM03. (Gabriel Novalski).06/08/2026: Redefined the Failure state byte: per-direction actuator capability bits (01h/02h gearbox extend/retract, 04h/08h throttle extend/retract, OR = unresponsive), 10h ESP overtemperature, 20h batterylow, 40h motor overcurrent, 80h reserved. BREAKING: old 02h/04h meanings changed. (Yuri)06/08/2026: Added ECUInfo that contains, battery voltage, motor current instant + peak since last frame,ESP temperature.(Yuri)19/08/2026: Added 0701h and 0707h device line unique code for both CM07.
```

## Identifiers

```
 | A | B | C | D | E | F | G | H | I
1
2 | CAN Identifier Organization |  | Priority Levels |  | Network Addresses
3 | Data | Position |  | Acronym | Value |  | Name | Value | Group
4 | Command | 0.0 -> 0.7 |  | Low | 11111b |  | BROADCAST | FFh | -
5 | Sender Address | 1.0 -> 1.7 |  | Normal | 00111b |  | COMPUTER/EXT TOOL | FEh | -
6 | Receiver Address | 2.0 -> 2.7 |  | High | 00011b |  | CM03 - THROLLING | 10h | ECU
7 | Priority | 3.0 -> 3.4 |  | Highest | 00000b |  | CM03/CM250 - PORT | 11h | ECU
8 |  |  |  |  |  |  | CM03/CM250 - STARBOARD | 12h | ECU
9 |  |  |  |  |  |  | CM01 | 2Xh | CTR
10 |  |  |  |  |  |  | Engine StartStop | 30h | PHR
11 |  |  |  |  |  |  | CM06 | 31h | PHR
12 |  |  |  |  |  |  | IVS-4180 | 30h + (8h + X) | PHR
13 |  |  |  |  |  |  | iVS-2008 | 4Xh | PHR
14 |  |  |  |  |  |  | CM02 | 5Xh | PHR
15 |  |  |  |  |  |  | Where "X" is the device instance
```

## Command Group

```
 | A | B | C | D | E | F | G | H
1 | Parameter Grup description table and its corresponding addresses.
2
3 | Group Label | Group Number | Acronym | Length | Priority | Direction | Period | Group Description
4 | Session | 00h | SEN | 8 bytes | Normal | From Device | - | Identification message containing basic device information.All the devices must send this identification message when joining the bus.Whenever a new device is detected, all the devices must identify themselves again.
5
6 | ECU Status | 02h | ECUS | 8 bytes | Normal | From Device | 50ms | Displays the ECU current gear, throttle, navigation mode and error states.
7 | ECU Block Status | 03h | ECUBS | 3 bytes | Normal | To/From Device | 500ms
8 | ECU Engage | 11h | ECUE | 1/2 bytes | High | To/From Device | -
9 | ECU Navigate | 12h | ECUN | 8 bytes | Normal | To Device | 50ms
10 | ECU Throlling | 13h | ECUT | TBD | Normal | To Device | 50ms
11 | ECU Linear Actuator State | 1Ah | ECULAS | 8 bytes | Low | From Device | 500ms | Displays current status of linear actuators, if any is present.
12 | ECU Linear Actuator Control | 1Bh | ECULAC | 4 bytes | High | To Device | 50_ms | Controls the ECU linear actuators, if any is present.
13 | ECU RPM Calibration Request | 1Dh | ECURCR | 8 bytes | High | To Device | - | Requests the ECU to calibrate the RPM input.
14 | ECU Engine Starter State | 21h | ECUESS | 4 bytes | High | From Device | 500ms
15 | ECU Engine Starter Request | 22h | ECUESR | 4 bytes | Highest/Low | To Device | 100/500ms
16
17 | CTR Status | 21h | CTRS | 6 bytes | Low | From Device | 100ms
18 | CTR Transfer | 22h | CTRT | 0/1 byte | High | To/From Device | -
19 | CTR Position Sensor | 23h | CTRPS | 8 bytes | Normal | From Device | 500ms | Current state of the Controller position sensor(usually a potentiometer).
20 | CTR Position Sensor Calibration | 24h | CTRPSC | 4 bytes | Normal | From Device | 500ms | Current calibration position (if requested).
21 | CM01 Maintenance | 31h | CM01M | 7 bytes | Low | From Device | 10s
22
23 | 2008 Digital Status | 41h | I2008DS | 3/4 bytes | Normal | To/From Device | 200ms
24 | 2008 Analog Status | 42h | I2008AS | 8 bytes | Low | From Device | 125ms
25
26 | IVS-4180 Channel Details | 51h | I4180CD | 8 bytes | Low | From Device | 750ms
27 | IVS-4180 Modify Rules | 54h | I4180MR | 2/8 bytes | High/Low | To/From Device | -
28 | IVS-4180 State | 58h | I4180S | 2/8 bytes | High/Low | To/From Device | -/500ms
29 | IVS-4180 Fail | FEh | I4180F | 8 bytes | High | From Device | 1000ms
30
31 | CM02 Status | 50h | CM02S | 8 bytes | Normal | From Device | 20ms | CM02 Position and sensors status.
32 | CM02 Command | 51h | CM02C | 8 bytes | Normal | From Device | 40ms | CM02 Position and sensors status.
```

## Parameter Group

```
 | A | B | C | D | E | F | G | H | I | J | K | L | M
1 | Parameter description table for each command, and its correponding data types.
2
3 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
4 | SEN | From Device | Device_Code | 0.0 -> 1.7 | Device line unique code.0101h - CM01.0302h - CM03v2.0303h - CM03v3.0701h - CM07B. (Botão)0707h - CM07D. (Digital/tela)2501h - CM250.2502h - CM250BT.4101h - CM02.
5 | SEN | From Device | FW_Major | 2.0 -> 2.3 | Runnig firmware version (major).
6 | SEN | From Device | FW_Minor | 2.4 -> 2.7 | Runnig firmware version (minor).
7 | SEN | From Device | Reserved | 3.0 -> 4.5 | Serial — NNNN (sequencial) - Unavailable = 0x1FFF
8 | SEN | From Device | Reserved | 4.6 -> 5.3 | Serial — DD (dia) - Unavailable = 0x3F.
9 | SEN | From Device | Reserved | 5.4 -> 5.7 | Serial — MM (mês) - Unavailable = 0x0F.
10 | SEN | From Device | Reserved | 6.0 -> 6.6 | Serial — AA (ano) - Unavailable = 0xEF.
11 | SEN | From Device | Reserved | 6.7 -> 7.7 | Reserved for future use
12
13 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
14 | ECUS | Fom Device | Mode | 0.0 -> 0.7 | Returns the current state of the ECU:00h - Idle                    -> No action can be performed.01h - Navigating              -> Normal operation.02h - Dock                    -> Acceleration is clamped to 20%.03h - Warmup Engine           -> No gears engage.04h - Throlling Valve Control -> No acceleration is performed.10h - Configuration           -> Cannot perform any action.11h - Fail                    -> Failure, see "Fail Bitstring"
15 | ECUS | Fom Device | Gear_State | 1.0 -> 1.7 | Current engaged gear status:00h - Neutral 01h - Forward02h - Backward1Xh - Moving XXXXXXThis state is bitwised OR with 10h when the ECU is stilltrying to reach the gear position.
16 | ECUS | Fom Device | Throttle | 2.0 -> 2.7 | Current throttle percentage.Factor = 1; 0h ~ 64h
17 | ECUS | Fom Device | Rpm | 3.0 -> 4.7 | Current rpm value read by the sensor or by the j1939 network.value is a 16 bit integer, big endian.u16 value = (*u8data << 8) | *(u8data + 1);
18 | ECUS | Fom Device | Fail | 5.0 -> 5.7 | Failure state.01h - Gearbox cannot extend.02h - Gearbox cannot retract.03h - Gearbox unresponsive (01h + 02h).04h - Throttle cannot extend.08h - Throttle cannot retract.0Ch - Throttle unresponsive (04h + 08h).10h - MCU overtemperature.20h - Battery low / Vin out of range.40h - Motor overcurrent.80h - Reserved.
19 | ECUS(> v2.0) | From Device | Reserved | 6.0 -> 6.7 | Reserved for future use
20 | ECUS(> v2.0) | From Device | Reserved | 7.0 -> 7.7 | Reserved for future use
21
22 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
23 | ECUBS | To/From Device | Block_State | 0.0 -> 0.3 | Status for the block0h -> Block Status Request.1h -> Block OFF (Disable)2h -> Block ON(Enable)Fh -> Error/Invalid state
24 | ECUBS | To/From Device | Block_Type | 0.4 -> 0.7 | Type of block to be applied1h -> Throttle2h -> RPMFh -> Invalid type
25 | ECUBS | To/From Device | Block_Value | 1.0 -> 2.7 | Limit value to be set0%-100% if Block Type == Throttle0-65,536 RPM if Block Type == RPM
26
27 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
28 | ECUE | To Device | Direction | 0.0 -> 0.7 | Engage direction.31h - In34h - Out
29
30 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
31 | ECUE | From Device | Ack | 0.0 -> 0.7 | ACK from ECU.01h - OK02h - Invalid parameter03h - Configuration mode04h - Already engaged
32 | ECUE | From Device | Engaged_Addr | 1.0 -> 0.7 | Address of the engaged device
33
34 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
35 | ECUN | To Device | Mode | 0.0 -> 0.7 | Set the ECU state. Read "Mode" from ECUS
36 | ECUN | To Device | Gear_State | 1.0 -> 1.7 | Set the ECU gear. Read "Gear State" ECUS
37 | ECUN | To Device | Throttle | 2.0 -> 2.7 | Set the ECU thottle percentage.Factor = 1; 0h to 64h
38 | ECUN(> v2.0) | To Device | Follow_RPM | 3.0 -> 4.7 | Asks the ECU to follow this RPM value, if not zero.u16 value = (*u8data << 8) | *(u8data + 1);
39 | ECUN(> v2.0) | To Device | Reserved | 5.0 -> 7.7 | Reserved for future use
40
41 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
42 | ECULAS | From Device | Actuator_№ | 0.0 -> 0.3 | Actuator number (identification).1h - Throttle actuator.2h - Gear actuator.
43 | ECULAS | From Device | Current_Position | 1.0 -> 1.7 | Current position in millimeters.Factor = 1; 0mm to 250mm.
44 | ECULAS | From Device | Target_Position | 2.0 -> 2.7 | Current position in millimeters.Factor = 1; 0mm to 250mm.
45 | ECULAS | From Device | Option_2 | 3.0 -> 3.7 | Configurted option position(2).Factor = 1; 0mm to 250mm.Throttle actuator: No usage.Gear actuator: No usage.
46 | ECULAS | From Device | Option_1 | 4.0 -> 4.7 | Configurted option position(1).Factor = 1; 0mm to 250mm.Throttle actuator: No usage.Gear actuator: Overshoot amount.
47 | ECULAS | From Device | Limits_3 | 5.0 -> 5.7 | Configurted position limits(3).Factor = 1; 0mm to 250mm.Throttle actuator: No usage.Gear actuator: Neutral position.
48 | ECULAS | From Device | Limits_2 | 6.0 -> 6.7 | Configurted position limits(2).Factor = 1; 0mm to 250mm.Throttle actuator: Full position.Gear actuator: Forward position.
49 | ECULAS | From Device | Limits_1 | 7.0 -> 7.7 | Configurted position limits(1).Factor = 1; 0mm to 250mm.Throttle actuator: Idle position.Gear actuator: Reverse position.
50
51 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
52 | ECULAC | To Device | Actuator_№ | 0.0 -> 0.3 | Actuator number (identification). Read "Actuator №" from ECULAS.
53 | ECULAC | To Device | Override_Action | 0.4 -> 0.7 | Override action code:1h - Advance in mm.2h - Reverse in mm.3h - Go absolute mm.9h - Stay in position.Ah - Save in limits 1.Bh - Save in limits 2.Ch - Save in limits 3.Dh - Save in options 1.Eh - Save in options 2.
54 | ECULAC | To Device | Parameter_Position | 1.0 -> 1.7 | Parameter position in mm.Factor = 1; 0mm to 250mm.
55 | ECULAC | To Device | Reserved | 2.0 -> 3.7 | Reserved for future use.
56
57 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
58 | ECURCR | To Device | Input_№ | 0.0 -> 0.7 | Select Input to use.01h - 15h
59 | ECURCR | To Device | Reserved | 1.0 -> 4.7 | Reserved for future use.
60 | ECURCR | To Device | Gear_Ratio | 5.0 -> 5.7 | Desired Gear Ratio, if any.Factor = 1; 0 to 250;
61 | ECURCR | To Device | Current_RPM | 6.0 -> 7.7 | Current RPM, if any.Factor = 1; 0 to 10,000rpm.
62
63 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
64 | ECUESS | From Device | Engine_Starter | 0.0 -> 0.3 | User Engine Starter Requested0h - Disable3h - No Demand7h - DemandedAny other combination shall be ignored.
65 | ECUESS | From Device | Engine_Cutoff | 0.4 -> 0.7 | User Engine Cutoff Requested0h - Disable3h - No Demand7h - DemandedAny other combination shall be ignored.
66 | ECUESS | From Device | Exception | 1.0 -> 1.7 | Reason for the command not being executed.00h - No reason, demand or no error.01h - Invalid state - Gear engaged.02h - Invalid state - Throttle not zeroed.04h - Invalid state - Improper startup.08h - Other ECU error, unmapped.F0h - Engine fault - See DTC.
67 | ECUESS | From Device | Engine_Status | 2.0 | Engine Status0b0 - Engine probably OFF0b1 - Engine probably ON
68 | ECUESS | From Device | Reserved | 2.1 -> 3.7 | Reserved for future use
69
70 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
71 | ECUESR | To Device | Engine Starter | 0.0 -> 0.3 | User Engine Starter Request. Read "Engine Starter" from ECUESS
72 | ECUESR | To Device | Engine Cutoff | 0.4 -> 0.7 | User Engine Cutoff Request. Read "Engine Cutoff" from ECUESS
73 | ECUESR | To Device | Reserved | 1.0 -> 4.7 | Reserved for future use
74
75 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
76 | CTRS | From Device | State | 0.0 -> 0.7 | Returns the current state of the Controller:01h - Idle                -> Performing no action.02h - Requesting Command  -> While asking for another CTR to command.04h - Commanding          -> While commanding the ECUs.10h - Self Testing        -> While performing self test.20h - Fail                -> Failure, see "Fail Bitstring"
77 | CTRS | From Device | IO_State | 1.0 -> 1.7 | Current open/closed I/O ports.01h - Engine Cuttoff on.02h - MIL on.
78 | CTRS | From Device | Error_Module | 2.0 -> 2.7 | Modules affected by or causing error.00h - When the system is fine.01h - Hardware level failure.02h - Navigator logic failure.04h - Network logic failure/incoherence.
79 | CTRS | From Device | Error_Code | 3.0 -> 3.7 | Error code based on module.TBD.
80 | CTRS | From Device | Product_Bitstr | 4.0 -> 4.7 | Product dependant bitsring.Non identified numbers are reserved for future implementation.0000b - CM200 01.0010b - CM300 01.1000b - CM06.
81 | CTRS | From Device | System_Ver_Maj | 5.0 -> 5.3 | System firmware Major version.
82 | CTRS | From Device | System_Ver_Min | 5.4 -> 5.7 | System firmware Minor version.
83
84 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
85 | CTRT | To Device | NO REQUEST DATA
86 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
87 | CTRT | From Device | State | 0.0 -> 0.7 | Transfer State, the CTR will keep sending this command until state changes.01h - Awaiting for ECU disconection  -> Perform no action.02h - Not able to complete transfer. -> Return to previous state.04h - Transfered                     -> Can command ECUs now.
88
89 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
90 | CTRPS | From Device | Throttle | 0.0 -> 0.7 | Throttle percentage if available.Factor = 0.4; 0h to FAh
91 | CTRPS | From Device | Throlling | 1.0 -> 1.7 | Throlling percentage if available.Factor = 0.4; 0h to FAh
92 | CTRPS | From Device | Gear | 2.0 -> 2.3 | Current gear if available.0h - Neutral.1h - Forward.2h - Backward.
93 | CTRPS | From Device | Reserved | 2.4 -> 6.3 | Reserved for future use.
94 | CTRPS | From Device | Strategy | 6.4 -> 6.7 | Control strategy.Potentiometer - 01hMagnetic (Hall Effect) - 02h
95 | CTRPS | From Device | Raw | 7.0 -> 7.7 | Raw value.Potentiometer - Factor = 0.72 ; 0h to FAh; DegMagnetic (Hall Effect) - Factor = 0.72 ; 0h to FAh; Deg
96
97 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
98 | CTRPSC | To Device | Position | 0.0 -> 0.7 | Calibration Position.max - 01hmin - 02hForward - 03hNeutral - 04hReverse - 05hNormalize - 10h
99 | CTRPSC | To Device | Reserved | 1.0 -> 3.7 | Reserved for future use.
100
101 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
102 | CM01M | From Device | State | 0.0 -> 0.7 | Maintenance data state.01h - Machine hours overrun.02h - Port side leveler cycles overrun.04h - Starbord side leveler cycles overrun.
103 | CM01M | From Device | Machine_hours | 1.0 -> 2.7 | Total machine hours since factory.
104 | CM01M | From Device | Port_Cycles | 3.0 -> 4.7 | Fracional(numerator = 10) port side leveler cycle since maintenance.No_of_cycles = (*u8data << 8) | *(u8data + 1);No_of_cycles /= 10;
105 | CM01M | From Device | Starboard_Cycles | 5.0 -> 6.7 | Fracional(numerator = 10) starboard side leveler cycle since maintenance.No_of_cycles = (*u8data << 8) | *(u8data + 1);No_of_cycles /= 10;
106
107 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
108 | I2008DS | From Device | Digital_Out_1 | 0.0 | Digital In State0b - Off.1b - On.
109 | I2008DS | From Device | Digital_Out_2 | 0.1 | Same as "Digital Out 1"
110 | I2008DS | From Device | Digital_Out_3 | 0.2 | Same as "Digital Out 1"
111 | I2008DS | From Device | Digital_Out_4 | 0.3 | Same as "Digital Out 1"
112 | I2008DS | From Device | Digital_Out_5 | 0.4 | Same as "Digital Out 1"
113 | I2008DS | From Device | Digital_Out_6 | 0.5 | Same as "Digital Out 1"
114 | I2008DS | From Device | Digital_Out_7 | 0.6 | Same as "Digital Out 1"
115 | I2008DS | From Device | Digital_Out_8 | 0.7 | Same as "Digital Out 1"
116 | I2008DS | From Device | Digital_In_1 | 1.0 | Same as "Digital Out 1"
117 | I2008DS | From Device | Digital_In_2 | 1.1 | Same as "Digital Out 1"
118 | I2008DS | From Device | Digital_In_3 | 1.2 | Same as "Digital Out 1"
119 | I2008DS | From Device | Digital_In_4 | 1.3 | Same as "Digital Out 1"
120 | I2008DS | From Device | Digital_In_5 | 1.4 | Same as "Digital Out 1"
121 | I2008DS | From Device | Digital_In_6 | 1.5 | Same as "Digital Out 1"
122 | I2008DS | From Device | Digital_In_7 | 1.6 | Same as "Digital Out 1"
123 | I2008DS | From Device | Digital_In_8 | 1.7 | Same as "Digital Out 1"
124 | I2008DS | From Device | Digital_In_9 | 2.0 | Same as "Digital Out 1"
125 | I2008DS | From Device | Digital_In_10 | 2.1 | Same as "Digital Out 1"
126 | I2008DS | From Device | Digital_In_11 | 2.2 | Same as "Digital Out 1"
127 | I2008DS | From Device | Digital_In_12 | 2.3 | Same as "Digital Out 1"
128 | I2008DS | From Device | N2K_Status | 2.4 -> 3.3 | Nmea 2000 Network State00h - Disconnected.10h - Connected.FFh - Error.
129 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
130 | I2008DS | To Device | Port_Mask | 0.0 -> 1.7 | Port Set Mask0b - The informed State will be Ignored.1b - The informed State will be Set.
131 | I2008DS | To Device | Port_State_Mask | 2.0 -> 3.7 | Port State Mask0b - Off.1b - On.
132
133 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
134 | I2008AS | To Device | Analog_Input | 0.0 -> 0.7 | Analog Input Mask01h - Analog Input 1.02h - Analog Input 2.03h - Analog Input 3.04h - Analog Input 4.05h - Analog Input 5.06h - Analog Input 6.07h - Analog Input 7.08h - Analog Input 8.
135 | I2008AS | To Device | Voltage | 1.0 -> 5.7 | Voltage of the informed Analog input.0 to 12V
136
137 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
138 | I4180CD | From Device | Voltage_IN_1 | 0.0 -> 1.3 | Input 1 Voltage RMS value.12 bit, fixed point (8.4) absolute RMS Voltage value.Sum up with a constant 80V to get the actual value.Any value lower than 1V or greater than 320V is invalid.
139 | I4180CD | From Device | Voltage_IN_2 | 1.4 -> 2.7 | Input 2 Voltage RMS value. Same as "Input 1".
140 | I4180CD | From Device | Voltage_IN_3 | 3.0 -> 4.3 | Input 3 Voltage RMS value. Same as "Input 1".
141 | I4180CD | From Device | Voltage_IN_4 | 4.4 -> 5.7 | Input 4 Voltage RMS value. Same as "Input 1".
142 | I4180CD | From Device | Reserved | 6.0 -> 7.7 | Reserved for future use.
143
144 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
145 | I4180S | From Device | Changing_Input | 0.0 | Flags if the device is changing the connected input.
146 | I4180S | From Device | Current_Input | 0.1 -> 0.3 | Current connected input.00h - Disconnected.01h - Input 1.02h - Input 2.03h - Input 3.04h - Input 4.
147 | I4180S | From Device | Output_Voltage | 0.4 -> 1.3 | Output RMS Voltage value.No decimals, absolute RMS Voltage value.Sum up with a constant 80V to get the actual value.Any value lower than 1V or greater than 320V is invalid.
148 | I4180S | From Device | Output_Current | 1.4 -> 2.7 | Output RMS Current value.12 bit, fixed point (8.4) absolute RMS Current value.Any value greater than 200A is invalid.
149 | I4180S | From Device | Current_Power_Usage | 3.0 -> 4.7 | Instantaneous output power.
150 | I4180S | From Device | State_Bits | 5.0 -> 5.3 | Current Device Configuration State.0000b - Normal Operation.0001b - Manual Mode.
151 | I4180S | From Device | Reserved | 5.4 -> 7.7 | Reserved for future use.
152
153 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
154 | I4180S | To Device | Change_Input | 0.0 | Flags if the device should change its input.
155 | I4180S | To Device | Input | 0.1 -> 0.3 | Connect to input.00h - Disconnect.01h - Input 1.02h - Input 2.03h - Input 3.04h - Input 4.
156 | I4180S | To Device | Reserved | 0.4 -> 1.7 | Reserved for future use.
157
158 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
159 | I4180MR | To Device | Change_Input | 0.0 | Flags if the device should change its input.
160 | I4180MR | To Device |  | 0.1 -> 0.3 | Connect to input.00h - Disconnect.01h - Input 1.02h - Input 2.03h - Input 3.04h - Input 4.
161 | I4180MR | To Device | Reserved | 0.4 -> 1.7 | Reserved for future use.
162
163 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
164 | I4180F | From Device | Error_Code | 0.0 -> 0.7 | Error code.
165 | I4180F | From Device | Unused | 1.0 -> 2.7 | Reserved for future use.
166 | I4180F | From Device | Timestamp | 3.0 -> 7.7 | Fail timestamp unix time, unsigned.
167
168 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
169 | CM02S | From Device | Position_Valid | 0.0 | 1 bit, TRUE/FALSE
170 | CM02S | From Device | Reserved | 0.1 -> 0.7 | Reserved for future use.
171 | CM02S | From Device | Last_Error_Code | 1.0 -> 1.7 | 00h - No Error.11h - Input voltage too low.12h - Input voltage too high.13h - Input current unable to sustain motor.21h - Power supply voltage too low.22h - Power supply voltage too high.31h - Positioning sensor open circuit.32h - Positioning sensor short circuit.41h - Motor unresponsive.
172 | CM02S | From Device | Position_mm | 2.0 -> 3.7 | Position in mm from sensor.Factor = 0.01526; 0000h to FFFAh; mm.
173 | CM02S | From Device | Vin_INT | 4.0 -> 4.4 | Vin Integral part.Factor = 1.0; 00h (0d) to 1Fh (37d); V.
174 | CM02S | From Device | Vin_FRAC | 4.5 -> 4.7 | Vin Fracional part.Factor = 0.125; 0h to 7h; V.
175 | CM02S | From Device | Reserved | 4.0 -> 7.7 | Reserved for future use.
176
177 | Group Acronym | Direction | Parameter Label | Parameter Position | Parameter Description
178 | CM02C | To Device | Reserved | 0.0 -> 0.7 | Reserved for future use.
179 | CM02C | To Device | Req_Position | 1.0 -> 2.7 | Position in mm.Factor = 0.01526; 0000h to FFFAh; mm.
180 | CM02C | To Device | Safe_Position | 3.0 -> 4.7 | Safe position in mm.Factor = 0.01526; 0000h to FFFAh; mm.
181 | CM02C | To Device | Reserved | 5.0 -> 7.7 | Reserved for future use.
```
