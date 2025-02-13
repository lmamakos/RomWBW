;
;==================================================================================================
; CENTRONICS (LPT) INTERFACE DRIVER
;==================================================================================================
;
; CENTRONICS-STYLE PARALLEL PRINTER DRIVER.  ASSUMES IBM STYLE
; HARDWARE INTERFACE AS DESCRIBED BELOW.
;
; IMPLEMENTED AS A ROMWBW CHARACTER DEVICE.  CURRENTLY HANDLES OUPUT
; ONLY.
;
;  PORT 0 (INPUT/OUTPUT):
;
;	D7	D6	D5	D4	D3	D2	D1	D0
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;     | PD7   | PD6   | PD5   | PD4   | PD3   | PD2   | PD1   | PD0   |
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;
;  PORT 1 (INPUT):
;
;	D7	D6	D5	D4	D3	D2	D1	D0
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;     | BUSY  | ACK   | POUT  | SEL   | ERR   | 0     | 0     | 0     |
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;
;  PORT 2 (INPUT/OUTPUT):
;
;	D7	D6	D5	D4	D3	D2	D1	D0
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;     | STAT1 | STAT0 | ENBL  | PINT  | SEL   | RES   | LF    | STB   |
;     +-------+-------+-------+-------+-------+-------+-------+-------+
;
LPT_NONE	.EQU	0		; NOT PRESENT
LPT_IBM		.EQU	1		; IBM PC STYLE INTERFACE
;
; PRE-CONSOLE INITIALIZATION - DETECT AND INIT HARDWARE
;
LPT_PREINIT:
;
; SETUP THE DISPATCH TABLE ENTRIES
; NOTE: INTS WILL BE DISABLED WHEN PREINIT IS CALLED AND THEY MUST REMIAIN
; DISABLED.
;
	LD	B,LPT_CFGCNT		; LOOP CONTROL
	XOR	A			; ZERO TO ACCUM
	LD	(LPT_DEV),A		; CURRENT DEVICE NUMBER
	LD	IY,LPT_CFG		; POINT TO START OF CFG TABLE
LPT_PREINIT0:
	PUSH	BC			; SAVE LOOP CONTROL
	CALL	LPT_INITUNIT		; HAND OFF TO UNIT INIT CODE
	POP	BC			; RESTORE LOOP CONTROL
;
	LD	A,(IY+1)		; GET THE LPT TYPE DETECTED
	OR	A			; SET FLAGS
	JR	Z,LPT_PREINIT2		; SKIP IT IF NOTHING FOUND
;
	PUSH	BC			; SAVE LOOP CONTROL
	PUSH	IY			; CFG ENTRY ADDRESS
	POP	DE			; ... TO DE
	LD	BC,LPT_FNTBL		; BC := FUNCTION TABLE ADDRESS
	CALL	NZ,CIO_ADDENT		; ADD ENTRY IF LPT FOUND, BC:DE
	POP	BC			; RESTORE LOOP CONTROL
;
LPT_PREINIT2:
	LD	DE,LPT_CFGSIZ		; SIZE OF CFG ENTRY
	ADD	IY,DE			; BUMP IY TO NEXT ENTRY
	DJNZ	LPT_PREINIT0		; LOOP UNTIL DONE
;
LPT_PREINIT3:
	XOR	A			; SIGNAL SUCCESS
	RET				; AND RETURN
;
; LPT INITIALIZATION ROUTINE
;
LPT_INITUNIT:
	CALL	LPT_DETECT		; DETERMINE LPT TYPE
	LD	(IY+1),A		; SAVE IN CONFIG TABLE
	OR	A			; SET FLAGS
	RET	Z			; ABORT IF NOTHING THERE
;
	; UPDATE WORKING LPT DEVICE NUM
	LD	HL,LPT_DEV		; POINT TO CURRENT DEVICE NUM
	LD	A,(HL)			; PUT IN ACCUM
	INC	(HL)			; INCREMENT IT (FOR NEXT LOOP)
	LD	(IY),A			; UPDATE UNIT NUM
;
	; SET DEFAULT CONFIG
	LD	DE,-1			; LEAVE CONFIG ALONE
	; CALL INITDEV TO IMPLEMENT CONFIG, BUT NOTE THAT WE CALL
	; THE INITDEV ENTRY POINT THAT DOES NOT ENABLE/DISABLE INTS!
	JP	LPT_INITDEVX		; IMPLEMENT IT AND RETURN
;
;
;
LPT_INIT:
	LD	B,LPT_CFGCNT		; COUNT OF POSSIBLE LPT UNITS
	LD	IY,LPT_CFG		; POINT TO START OF CFG TABLE
LPT_INIT1:
	PUSH	BC			; SAVE LOOP CONTROL
	LD	A,(IY+1)		; GET LPT TYPE
	OR	A			; SET FLAGS
	CALL	NZ,LPT_PRTCFG		; PRINT IF NOT ZERO
	POP	BC			; RESTORE LOOP CONTROL
	LD	DE,LPT_CFGSIZ		; SIZE OF CFG ENTRY
	ADD	IY,DE			; BUMP IY TO NEXT ENTRY
	DJNZ	LPT_INIT1		; LOOP TILL DONE
;
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
; DRIVER FUNCTION TABLE
;
LPT_FNTBL:
	.DW	LPT_IN
	.DW	LPT_OUT
	.DW	LPT_IST
	.DW	LPT_OST
	.DW	LPT_INITDEV
	.DW	LPT_QUERY
	.DW	LPT_DEVICE
#IF (($ - LPT_FNTBL) != (CIO_FNCNT * 2))
	.ECHO	"*** INVALID LPT FUNCTION TABLE ***\n"
	!!!	; FORCE AN ASSEMBLY ERROR
#ENDIF
;
; BYTE INTPUT
;
LPT_IN:
	; INPUT NOT SUPPORTED - RETURN NULL BYTE
	LD	E,0			; NULL BYTE
	XOR	A			; SIGNAL SUCCESS
	RET
;
; BYTE OUTPUT
;
LPT_OUT:
	CALL	LPT_OST			; READY TO SEND?
	JR	Z,LPT_OUT		; LOOP IF NOT
	LD	A,(IY+3)
	LD	C,A			; PORT 0 (DATA)
 	OUT	(C),E			; OUTPUT DATA TO PORT
 	CALL 	DELAY   		; IGNORE ANYTHING BACK AFTER A RESET
        LD      A,%00001101             ; SELECT & STROBE, LEDS OFF
	INC 	C 			; PUT CONTROL PORT IN C
	INC 	C
        OUT	(C),A			; OUTPUT DATA TO PORT
  	CALL 	DELAY   		; IGNORE ANYTHING BACK AFTER A RESET
        LD      A,%00001100             ; SELECT, LEDS OFF
        OUT	(C),A			; OUTPUT DATA TO PORT

	XOR	A			; SIGNAL SUCCESS
	RET
;
; INPUT STATUS
;
LPT_IST:
	; INPUT NOT SUPPORTED - RETURN NOT READY
	XOR	A			; ZERO BYTES AVAILABLE
	RET				; DONE
;
; OUTPUT STATUS
;
LPT_OST:
	LD	A,(IY+3)
	LD	C,A			; PORT 0 (DATA)
	INC 	C			; SELECT STATUS PORT
 	IN	A,(C)			; GET STATUS INFO
    	AND	%10000000		; ONLY INTERESTED IN BUSY FLAG
	RET				; DONE
;
; INITIALIZE DEVICE
;
LPT_INITDEV:
	HB_DI				; AVOID CONFLICTS
	CALL	LPT_INITDEVX		; DO THE REAL WORK
	HB_EI				; INTS BACK ON
	RET				; DONE
;
; THIS ENTRY POINT BYPASSES DISABLING/ENABLING INTS WHICH IS REQUIRED BY
; PREINIT ABOVE.  PREINIT IS NOT ALLOWED TO ENABLE INTS!
;
LPT_INITDEVX:
	LD	A,(IY+3)
	LD	C,A			; PORT 0 (DATA)
	XOR	A			; CLEAR ACCUM
	OUT	(C),A			; SEND IT
	INC	C			; BUMP TO
	INC	C			; ... PORT 2
	LD	A,%00001000		; SELECT AND ASSERT RESET, LEDS OFF
	OUT	(C),A			; SEND IT
 	CALL	LDELAY			; HALF SECOND DELAY
	LD	A,%00001100		; SELECT AND DEASSERT RESET, LEDS OFF
	OUT	(C),A			; SEND IT
	XOR	A			; SIGNAL SUCCESS
	RET				; RETURN
;
;
;
LPT_QUERY:
	LD	E,(IY+4)		; FIRST CONFIG BYTE TO E
	LD	D,(IY+5)		; SECOND CONFIG BYTE TO D
	XOR	A			; SIGNAL SUCCESS
	RET				; DONE
;
;
;
LPT_DEVICE:
	LD	D,CIODEV_LPT		; D := DEVICE TYPE
	LD	E,(IY)			; E := PHYSICAL UNIT
	LD	C,$40			; C := DEVICE TYPE, 0x40 IS PIO
	LD	H,(IY+1)		; H := MODE
	LD	L,(IY+3)		; L := BASE I/O ADDRESS
	XOR	A			; SIGNAL SUCCESS
	RET
;
; LPT DETECTION ROUTINE
;
LPT_DETECT:
	LD	A,(IY+3)		; BASE PORT ADDRESS
	LD	C,A			; PUT IN C FOR I/O
	CALL	LPT_DETECT2		; CHECK IT
	JR	Z,LPT_DETECT1		; FOUND IT, RECORD IT
	LD	A,LPT_NONE		; NOTHING FOUND
	RET				; DONE
;
LPT_DETECT1:
	; LPT FOUND, RECORD IT
	LD	A,LPT_IBM		; RETURN CHIP TYPE
	RET				; DONE
;
LPT_DETECT2:
	; LOOK FOR LPT AT BASE PORT ADDRESS IN C
	INC	C			; PORT C FOR I/O
	INC	C			; ...
	XOR	A			; DEFAULT VALUE (TRI-STATE OFF)
	OUT	(C),A			; SEND IT
;
	;IN	A,(C)			; READ IT
	;AND	%11000000		; ISOLATE STATUS BITS
	;CP	%00000000		; CORRECT VALUE?
	;RET	NZ			; IF NOT, RETURN
	;LD	A,%11000000		; STATUS BITS ON (LEDS OFF)
	;OUT	(C),A			; SEND IT
	;IN	A,(C)			; READ IT
	;AND	%11000000		; ISOLATE STATUS BITS
	;CP	%11000000		; CORRECT VALUE?
;
	DEC	C			; BACK TO BASE PORT
	DEC	C			; ...
	LD	A,$A5			; TEST VALUE
	OUT	(C),A			; SEND IT
	IN	A,(C)			; READ IT BACK
	CP	$A5			; CORRECT?
	RET				; RETURN (ZF SET CORRECTLY)
;
;
;
LPT_PRTCFG:
	; ANNOUNCE PORT
	CALL	NEWLINE			; FORMATTING
	PRTS("LPT$")			; FORMATTING
	LD	A,(IY)			; DEVICE NUM
	CALL	PRTDECB			; PRINT DEVICE NUM
	PRTS(": IO=0x$")		; FORMATTING
	LD	A,(IY+3)		; GET BASE PORT
	CALL	PRTHEXBYTE		; PRINT BASE PORT

	; PRINT THE LPT TYPE
	CALL	PC_SPACE		; FORMATTING
	LD	A,(IY+1)		; GET LPT TYPE BYTE
	RLCA				; MAKE IT A WORD OFFSET
	LD	HL,LPT_TYPE_MAP		; POINT HL TO TYPE MAP TABLE
	CALL	ADDHLA			; HL := ENTRY
	LD	E,(HL)			; DEREFERENCE
	INC	HL			; ...
	LD	D,(HL)			; ... TO GET STRING POINTER
	CALL	WRITESTR		; PRINT IT
;
	; ALL DONE IF NO LPT WAS DETECTED
	LD	A,(IY+1)		; GET LPT TYPE BYTE
	OR	A			; SET FLAGS
	RET	Z			; IF ZERO, NOT PRESENT
;
	; *** ADD MORE DEVICE INFO??? ***
;
	XOR	A
	RET
;
;
;
LPT_TYPE_MAP:
		.DW	LPT_STR_NONE
		.DW	LPT_STR_IBM
;
LPT_STR_NONE	.DB	"<NOT PRESENT>$"
LPT_STR_IBM	.DB	"IBM$"
;
; WORKING VARIABLES
;
LPT_DEV		.DB	0		; DEVICE NUM USED DURING INIT
;
; LPT DEVICE CONFIGURATION TABLE
;
LPT_CFG:
;
LPT0_CFG:
	; LPT MODULE A CONFIG
	.DB	0			; DEVICE NUMBER (SET DURING INIT)
	.DB	0			; LPT TYPE (SET DURING INIT)
	.DB	0			; MODULE ID
	.DB	LPT0BASE		; BASE PORT
	.DW	0			; LINE CONFIGURATION
;
LPT_CFGSIZ	.EQU	$ - LPT_CFG	; SIZE OF ONE CFG TABLE ENTRY
;
#IF (LPTCNT >= 2)
;
LPT1_CFG:
	; LPT MODULE B CONFIG
	.DB	0			; DEVICE NUMBER (SET DURING INIT)
	.DB	0			; LPT TYPE (SET DURING INIT)
	.DB	1			; MODULE ID
	.DB	LPT1BASE		; BASE PORT
	.DW	0			; LINE CONFIGURATION
;
#ENDIF
;
LPT_CFGCNT	.EQU	($ - LPT_CFG) / LPT_CFGSIZ
