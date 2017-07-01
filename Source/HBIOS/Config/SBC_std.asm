;
;==================================================================================================
;   SBC STANDARD CONFIGURATION
;==================================================================================================
;
#include "cfg_sbc.asm"
;
FDENABLE	.SET	FALSE		; TRUE FOR FLOPPY DEVICE SUPPORT
FDMODE		.SET	FDMODE_DIO3	; FDMODE_DIO, FDMODE_DIDE, FDMODE_DIO3
;
IDEENABLE	.SET	FALSE		; TRUE FOR IDE DEVICE SUPPORT
IDEMODE		.SET	IDEMODE_DIO	; IDEMODE_DIO, IDEMODE_DIDE
;
PPIDEENABLE	.SET	TRUE		; TRUE FOR PPIDE DEVICE SUPPORT
PPIDEMODE	.SET	PPIDEMODE_SBC	; PPIDEMODE_SBC, PPPIDEMODE_DIO3, PPIDEMODE_MFP
;
SDENABLE	.SET	FALSE		; TRUE FOR SD DEVICE SUPPORT
SDMODE		.SET	SDMODE_PPI	; SDMODE_JUHA, SDMODE_PPI, SDMODE_DSD
;
PRPENABLE	.SET	TRUE		; TRUE FOR PROPIO BOARD SUPPORT (VIDEO, KBD, & SD CARD)
;
VGAENABLE	.SET	TRUE		; TRUE FOR VGA BOARD VIDEO & KBD SUPPORT
CVDUENABLE	.SET	TRUE		; TRUE FOR CVDU BOARD VIDEO & KBD SUPPORT
VDUENABLE	.SET	FALSE		; TRUE FOR VDU BOARD VIDEO & KBD SUPPORT
;
CRTACT		.SET	FALSE		; TRUE TO ACTIVATE CRT AT STARTUP (BOOT ON CRT)
