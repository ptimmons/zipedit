*--------------------------------------
* PRNPROBE.S -- what is in slot 1, and how does it want to be driven?
*
* Built for one question before the editor learns to print: does the
* parallel card in slot 1 speak the Pascal 1.1 firmware protocol, or does it
* only answer PR#1? The two are driven differently, and the answer is in the
* card's ROM, not in any emulator.
*
*   - the Pascal 1.1 signature: $Cn05 = $38, $Cn07 = $18, $Cn0B = $01, with
*     the init and write entry offsets at $Cn0D and $Cn0F
*   - whether the ROM reads steadily at all: an empty slot reads the floating
*     bus, which changes from one read to the next
*   - all 256 bytes of $C100-$C1FF, two screens of them, to photograph
*
* Then two tests that put ink on paper:
*
*   P   two lines through the Pascal write entry, bit 7 clear. If they land
*       on top of each other, the card does not add a line feed to a return.
*   H   two lines through PR#1 -- the output hook pointed at $C100 -- one with
*       bit 7 set, as BASIC sends it, and one with it clear. An FX-80 prints
*       codes $80-$FF in italics, so an italic first line means the card
*       passes bit 7 straight through.
*
* Plain 6502, monitor COUT at 40 columns, like keyprobe.S: it has to run on
* whatever machine the card is in. RESET stops it.
*--------------------------------------
             org   $2000
             typ   $ff
             dsk   PRNPROBE.SYSTEM

KBD          equ   $c000
KBDSTRB      equ   $c010
HOME         equ   $fc58
CROUT        equ   $fd8e
PRBYTE       equ   $fdda               ; A as two hex digits, through COUT
COUT         equ   $fded
SLOTROM      equ   $c100               ; slot 1's ROM page
CSWL         equ   $36                 ; the monitor's output hook
PSTR         equ   $06                 ; zero page: (PSTR),y needs it there
PTR          equ   $08                 ; 2 bytes, the dump's read pointer
ROWS         equ   $0a                 ; dump rows left on this screen
SUM          equ   $0b
IDX          equ   $0c                 ; place in the string being sent
VEC          equ   $0d                 ; 2 bytes, the Pascal entry being called
PERR         equ   $0f                 ; X from the last Pascal write
SAVCSW       equ   $1a                 ; 2 bytes, the hook before PR#1

START        jsr   HOME
             lda   #<BANNER
             ldy   #>BANNER
             jsr   PUTS

*--- the signature bytes, whatever they are
             lda   SLOTROM+$05
             jsr   PRBYTE
             jsr   SPACE
             lda   SLOTROM+$07
             jsr   PRBYTE
             jsr   SPACE
             lda   SLOTROM+$0b
             jsr   PRBYTE
             jsr   SPACE
             lda   SLOTROM+$0c
             jsr   PRBYTE
             jsr   CROUT

             jsr   PASCAL
             bcs   :nopas
             lda   #<MSGPASY
             ldy   #>MSGPASY
             jsr   PUTS
             lda   SLOTROM+$0d
             jsr   PRBYTE
             lda   #<MSGWRT
             ldy   #>MSGWRT
             jsr   PUTS
             lda   SLOTROM+$0f
             jsr   PRBYTE
             jsr   CROUT
             jmp   :steady
:nopas       lda   #<MSGPASN
             ldy   #>MSGPASN
             jsr   PUTS

:steady      jsr   STABLE
             bcs   :float
             lda   #<MSGROMY
             ldy   #>MSGROMY
             jsr   PUTS
             jmp   :dump
:float       lda   #<MSGROMN
             ldy   #>MSGROMN
             jsr   PUTS

:dump        lda   #<MSGDUMP
             ldy   #>MSGDUMP
             jsr   PUTS
             jsr   WAITKEY
             lda   #<SLOTROM
             sta   PTR
             lda   #>SLOTROM
             sta   PTR+1
             jsr   DUMP128
             lda   #<MSGMORE
             ldy   #>MSGMORE
             jsr   PUTS
             jsr   WAITKEY
             jsr   DUMP128             ; PTR carries on from $C180

*--- the tests, as often as wanted
MENU         lda   #<MSGMENU
             ldy   #>MSGMENU
             jsr   PUTS
:key         jsr   WAITKEY
             and   #$df                ; fold a lowercase letter to a capital
             cmp   #$d0                ; P
             bne   :h
             jsr   TESTPAS
             jmp   MENU
:h           cmp   #$c8                ; H
             bne   :key
             jsr   TESTHOOK
             jmp   MENU

*--------------------------------------
* PASCAL -- carry clear if slot 1 carries the Pascal 1.1 signature
*--------------------------------------
PASCAL       lda   SLOTROM+$05
             cmp   #$38
             bne   :no
             lda   SLOTROM+$07
             cmp   #$18
             bne   :no
             lda   SLOTROM+$0b
             cmp   #$01
             bne   :no
             clc
             rts
:no          sec
             rts

*--------------------------------------
* STABLE -- carry clear if slot 1 reads like a ROM
*
* An empty slot reads the floating bus: whatever video byte the hardware
* fetched that cycle, which drifts between reads. A ROM reads the same every
* time. A blank screen is the trap -- it floats as one byte, $A0, over and
* over, and that is steady too -- so a page of one repeated byte fails.
* Only $C100-$C13F counts: a card's ROM need not fill the page, and on
* PT's Epson APL card $C1C0-$C1FF floats.
*--------------------------------------
STABLE       jsr   SUMROM
             sta   SUM
             jsr   SUMROM
             cmp   SUM
             bne   :no
             ldx   #$00
:same        lda   SLOTROM,x
             cmp   SLOTROM
             bne   :yes
             inx
             cpx   #$40                ; the first 64 bytes only: see above
             bne   :same
:no          sec
             rts
:yes         clc
             rts

SUMROM       lda   #$00
             tax
             clc
:loop        adc   SLOTROM,x
             inx
             cpx   #$40                ; the first 64 bytes only: see above
             bne   :loop
             rts

*--------------------------------------
* DUMP128 -- a fresh screen of 16 rows of 8 bytes from PTR, advancing it
*--------------------------------------
DUMP128      jsr   HOME
             lda   #16
             sta   ROWS
:row         lda   PTR+1
             jsr   PRBYTE
             lda   PTR
             jsr   PRBYTE
             lda   #$ba                ; ':'
             jsr   COUT
             ldy   #$00
:byte        lda   #$a0
             jsr   COUT                ; the monitor's COUT preserves Y
             lda   (PTR),y
             jsr   PRBYTE
             iny
             cpy   #$08
             bne   :byte
             jsr   CROUT
             lda   PTR
             clc
             adc   #$08
             sta   PTR
             dec   ROWS
             bne   :row
             rts

*--------------------------------------
* TESTPAS -- init, then two lines through the Pascal write entry
*--------------------------------------
TESTPAS      jsr   PASCAL
             bcc   :go
             lda   #<MSGNOPAS
             ldy   #>MSGNOPAS
             jmp   PUTS

:go          lda   SLOTROM+$0d         ; init
             sta   VEC
             lda   #>SLOTROM
             sta   VEC+1
             jsr   CALLPAS
             lda   SLOTROM+$0f         ; and from now on, write
             sta   VEC
             lda   #<LINEP1
             sta   PSTR
             lda   #>LINEP1
             sta   PSTR+1
             jsr   SENDPAS
             lda   #<LINEP2
             sta   PSTR
             lda   #>LINEP2
             sta   PSTR+1
             jsr   SENDPAS
             lda   #<MSGSENT
             ldy   #>MSGSENT
             jsr   PUTS
             lda   PERR
             jsr   PRBYTE
             jmp   CROUT

*--- every byte of a low-ASCII string, X = $Cn and Y = $n0 as the protocol asks
SENDPAS      lda   #$00
             sta   IDX
:loop        ldy   IDX
             lda   (PSTR),y
             beq   :done
             jsr   CALLPAS
             stx   PERR                ; the protocol returns its error in X
             inc   IDX
             jmp   :loop
:done        rts

CALLPAS      ldx   #>SLOTROM
             ldy   #$10
             jmp   (VEC)

*--------------------------------------
* TESTHOOK -- two lines through PR#1, then the hook put back
*--------------------------------------
TESTHOOK     jsr   STABLE
             bcc   :go
             lda   #<MSGNOHK
             ldy   #>MSGNOHK
             jmp   PUTS

:go          lda   CSWL
             sta   SAVCSW
             lda   CSWL+1
             sta   SAVCSW+1
             lda   #<SLOTROM           ; what PR#1 does
             sta   CSWL
             lda   #>SLOTROM
             sta   CSWL+1

             lda   #<LINEH1            ; bit 7 set, as BASIC would send it
             sta   PSTR
             lda   #>LINEH1
             sta   PSTR+1
             lda   #$80
             jsr   SENDHK

             lda   #<LINEH2            ; and clear
             sta   PSTR
             lda   #>LINEH2
             sta   PSTR+1
             lda   #$00                ; sent as it is
             jsr   SENDHK

             lda   SAVCSW              ; PR#0, in effect
             sta   CSWL
             lda   SAVCSW+1
             sta   CSWL+1
             lda   #<MSGHKOK
             ldy   #>MSGHKOK
             jmp   PUTS

*--- every byte of the string at PSTR through COUT, ORed with A. The card's
*    firmware is under no obligation to preserve Y, so the place is kept in
*    memory.
SENDHK       sta   SUM
             lda   #$00
             sta   IDX
:loop        ldy   IDX
             lda   (PSTR),y
             beq   :done
             ora   SUM
             jsr   COUT
             inc   IDX
             jmp   :loop
:done        rts

*--------------------------------------
* WAITKEY -- block for a key and return it in A
*--------------------------------------
WAITKEY      lda   KBD
             bpl   WAITKEY
             sta   KBDSTRB
             rts

SPACE        lda   #$a0
             jmp   COUT

*--------------------------------------
* PUTS -- print the null-terminated string at A,Y
*--------------------------------------
PUTS         sta   PSTR
             sty   PSTR+1
             ldy   #$00
:loop        lda   (PSTR),y
             beq   :done
             jsr   COUT
             iny
             bne   :loop
             inc   PSTR+1
             bne   :loop
:done        rts


BANNER       asc   "ZIPEDIT PRINTER PROBE -- SLOT 1"
             dfb   $8d,$8d
             asc   "C105 C107 C10B C10C"
             dfb   $8d
             asc   "  38   18   01  1X  = PASCAL 1.1"
             dfb   $8d
             dfb   $00
MSGPASY      asc   "PASCAL 1.1: YES  INIT C1"
             dfb   $00
MSGWRT       asc   " WRITE C1"
             dfb   $00
MSGPASN      asc   "PASCAL 1.1: NO"
             dfb   $8d,$00
MSGROMY      asc   "ROM: READS STEADY"
             dfb   $8d,$00
MSGROMN      asc   "ROM: UNSTEADY -- IS THE SLOT EMPTY?"
             dfb   $8d,$00
MSGDUMP      dfb   $8d
             asc   "PHOTOGRAPH THIS SCREEN, THEN THE"
             dfb   $8d
             asc   "TWO THAT FOLLOW. ANY KEY TO GO ON."
             dfb   $8d,$00
MSGMORE      asc   "ANY KEY FOR $C180-$C1FF"
             dfb   $00
MSGMENU      dfb   $8d
             asc   "PRINTER ON, PAPER IN, THEN:"
             dfb   $8d
             asc   "  P  TEST THE PASCAL ENTRY"
             dfb   $8d
             asc   "  H  TEST PR#1"
             dfb   $8d
             asc   "RESET STOPS IT."
             dfb   $8d,$00
MSGNOPAS     asc   "NO PASCAL ENTRY POINTS ON THIS CARD."
             dfb   $8d,$00
MSGNOHK      asc   "NOTHING STEADY IN SLOT 1. NOT CALLING"
             dfb   $8d
             asc   "INTO IT."
             dfb   $8d,$00
MSGSENT      asc   "SENT. LAST ERROR CODE "
             dfb   $00
MSGHKOK      dfb   $8d
             asc   "SENT TWO LINES THROUGH PR#1."
             dfb   $8d,$00

*--- what goes to the printer: low ASCII, single quotes
LINEP1       asc   'ZipEdit probe: Pascal entry, line 1'
             dfb   $0d,$00
LINEP2       asc   'ZipEdit probe: Pascal entry, line 2'
             dfb   $0d,$00
LINEH1       asc   'ZipEdit probe: PR#1, bit 7 set'
             dfb   $0d,$00
LINEH2       asc   'ZipEdit probe: PR#1, bit 7 clear'
             dfb   $0d,$00
