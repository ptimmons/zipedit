*--------------------------------------
* PRINT.S -- the document on a parallel printer in slot 1 (OA-P, Esc Ctrl-P)
*
* Written against an Epson FX-80 on a parallel card in slot 1, which is the
* machine it was asked for. Anything that takes the FX-80's escape codes will
* do; anything in slot 1 that is not a printer card is refused before it is
* called, as far as that can be told -- see PRFIND.
*
* WHAT GOES ON THE PAPER IS WHAT IS ON THE SCREEN. Saving puts only the
* writer's own returns in the file and leaves the wrapping to whoever reads it.
* A printer is not a reader that wraps, and the editor already laid every line
* out against a margin at column 76 -- inside the FX-80's 80 -- so every break
* in the buffer, all three kinds, becomes a return here. Paper matches the
* screen line for line.
*
* BIT 7. Everything in the buffer is high ASCII, and an FX-80 prints $80-$FF
* in italics. The Pascal path sends every byte with bit 7 clear. The PR#1
* path sends it as PRHI says: set, by default, the way BASIC sends it, which
* leaves the stripping to the card's firmware as PR#1 from BASIC always has.
* A card that passes bit 7 through would italicise the page and turn the 6 of
* ESC N 6 into 134, so it wants PRHI cleared. src/prnprobe.S asks the card.
*
* TWO WAYS IN, chosen by what the card's ROM says about itself:
*
*   Pascal 1.1   $Cn05 = $38, $Cn07 = $18, $Cn0B = $01. Init and write are
*                at $Cn00 plus the offsets in $Cn0D and $Cn0F, called with
*                X = $Cn and Y = $n0. Nothing is echoed to the screen.
*   PR#1         the monitor's output hook pointed at $C100 and every byte
*                sent through COUT, exactly what PR#1 does. The card may echo
*                to the screen through the monitor's 40-column routine, so
*                the screen is repainted afterwards.
*
* THE ZERO PAGE IS NOT OURS WHILE FIRMWARE RUNS. The monitor's screen routine
* keeps its cursor and row base at $24-$29, and the editor keeps SCROLLTOP,
* LINENO and CURLNO there. A card that echoes would write wherever the
* editor's line numbers happened to point. So the whole zero page is put
* aside first and the monitor is given a window of its own to scribble in,
* and everything the walk needs afterwards -- the gap, its own position --
* lives outside zero page until the page is put back.
*
* Esc between lines stops it. Inside a line, and while the printer is offline,
* the card's firmware is waiting on the printer and nothing can interrupt it.
*--------------------------------------

PRSLOT       equ   $c1                 ; slot 1, as a ROM page
PRROM        equ   $c100
PRESC        equ   $1b
CSWL         equ   $36                 ; the monitor's output hook
WNDLFT       equ   $20                 ; the monitor's text window, and its
WNDWDTH      equ   $21                 ; cursor, which the PR#1 path's echo
WNDTOP       equ   $22                 ; draws with
WNDBTM       equ   $23
CH           equ   $24
CV           equ   $25
INVFLG       equ   $32
VTAB         equ   $fc22               ; row base from CV
COUT         equ   $fded
PRZP         equ   $1500               ; a page, for the zero page while
                                       ; firmware runs. $1500-$1FFF is unused in
                                       ; all three builds.

*--------------------------------------
* KPRINT -- print the whole document
*--------------------------------------
KPRINT       lda   #<MSGPRINTING
             sta   STRPTR
             lda   #>MSGPRINTING
             sta   STRPTR+1
             jsr   SHOWBUSY
             jsr   PRFIND
             bcc   :found
             lda   #<MSGNOPRN
             sta   STRPTR
             lda   #>MSGNOPRN
             sta   STRPTR+1
             jmp   SHOWMSG

:found       jsr   PROPEN

*--- ESC @ resets the printer and makes this line the top of the page; ESC N 6
*    skips the last six lines of each page, over the perforation.
             lda   #PRESC
             jsr   PROUT
             lda   #$40                ; @
             jsr   PROUT
             lda   #PRESC
             jsr   PROUT
             lda   #$4e                ; N
             jsr   PROUT
             lda   #$06
             jsr   PROUT

             lda   #$00
             sta   PRPOS
             lda   #BUFLO
             sta   PRPOS+1

:loop        lda   PRPOS               ; standing at the gap? jump over it
             cmp   PRGAPB
             bne   :notgap
             lda   PRPOS+1
             cmp   PRGAPB+1
             bne   :notgap
             lda   PRGAPE
             sta   PRPOS
             lda   PRGAPE+1
             sta   PRPOS+1

:notgap      lda   PRPOS+1             ; ran off the end of the buffer?
             cmp   #BUFHI
             bcs   :end
             lda   PRPOS               ; AUXPTR is put back for every byte:
             sta   AUXPTR              ; the firmware may have used it
             lda   PRPOS+1
             sta   AUXPTR+1
             ldy   #$00
             jsr   AUXRD
             cmp   #TEXTLO
             bcs   :text

*--- a break of any kind: a return, and a chance to stop
             jsr   PRNL
             lda   KBD
             cmp   #$9b                ; Esc, waiting in the latch
             bne   :next
             sta   KBDSTRB
             jsr   PRCLOSE
             lda   #<MSGPRSTOP
             sta   STRPTR
             lda   #>MSGPRSTOP
             sta   STRPTR+1
             jmp   SHOWMSG

:text        and   #$7f
             jsr   PROUT
:next        inc   PRPOS
             bne   :loop
             inc   PRPOS+1
             jmp   :loop

:end         jsr   PRNL                ; a last line with no return of its own
             lda   #$0c                ; form feed: the page out of the printer
             jsr   PROUT
             jsr   PRCLOSE
             jmp   RESTORESTAT         ; the busy notice was the feedback

*--------------------------------------
* PRFIND -- what is in slot 1? Carry clear and PRMODE set if it can be driven.
*
* With no Pascal signature the only way in is to jump into the ROM, so
* something had better be there. An empty slot reads the floating bus --
* whatever video byte the hardware fetched that cycle, which drifts between
* reads -- while a ROM reads the same every time. A blank screen is the trap:
* it floats as $A0 over and over, which is steady too, so a page of one
* repeated byte does not count.
*--------------------------------------
PRFIND       lda   PRROM+$05
             cmp   #$38
             bne   :hook
             lda   PRROM+$07
             cmp   #$18
             bne   :hook
             lda   PRROM+$0b
             cmp   #$01
             bne   :hook
             lda   #$00
             sta   PRMODE
             clc
             rts

:hook        jsr   PRSUM
             sta   TMPA
             jsr   PRSUM
             cmp   TMPA
             bne   :none
             ldx   #$00
:same        lda   PRROM,x
             cmp   PRROM
             bne   :rom
             inx
             bne   :same
:none        sec
             rts
:rom         lda   #$01
             sta   PRMODE
             clc
             rts

PRSUM        lda   #$00
             tax
             clc
:loop        adc   PRROM,x
             inx
             bne   :loop
             rts

*--------------------------------------
* PROPEN -- put the zero page aside and wake the card
*--------------------------------------
PROPEN       ldx   #$00
:save        lda   $00,x
             sta   PRZP,x
             inx
             bne   :save
             lda   GAPBEG              ; the walk's copy of the gap, out of
             sta   PRGAPB              ; reach of the firmware
             lda   GAPBEG+1
             sta   PRGAPB+1
             lda   GAPEND
             sta   PRGAPE
             lda   GAPEND+1
             sta   PRGAPE+1

             sta   MAINWR              ; firmware keeps its state in the screen
                                       ; holes, which must be main's, not aux's
             lda   PRMODE
             bne   :hook
             lda   PRROM+$0d           ; Pascal init
             sta   PRVEC
             lda   #PRSLOT
             sta   PRVEC+1
             jsr   PRCALL
             lda   PRROM+$0f           ; and write, from now on
             sta   PRVEC
             rts

*--- PR#1. The echo, if the card makes one, gets a full-width window and the
*    bottom row, and the screen is repainted when printing is over.
:hook        lda   #$00
             sta   WNDLFT
             sta   WNDTOP
             sta   CH
             lda   #40
             sta   WNDWDTH
             lda   #24
             sta   WNDBTM
             lda   #23
             sta   CV
             lda   #$ff                ; normal video
             sta   INVFLG
             jsr   VTAB
             lda   #<PRROM
             sta   CSWL
             lda   #PRSLOT
             sta   CSWL+1
             rts

*--------------------------------------
* PROUT -- send the byte in A, given with bit 7 clear, whichever way PRFIND
*          chose
*--------------------------------------
PROUT        sta   MAINWR              ; STA leaves A alone
             ldx   PRMODE
             beq   PRCALL
             ora   PRHI                ; PR#1: bit 7 as PRHI says
             jmp   COUT
PRCALL       ldx   #PRSLOT             ; Pascal: X = $Cn, Y = $n0
             ldy   #$10
             jmp   (PRVEC)

*--------------------------------------
* PRNL -- end a line
*--------------------------------------
PRNL         lda   #$0d
             jsr   PROUT
             lda   PRLF
             beq   :done
             lda   #$0a
             jsr   PROUT
:done        rts

*--------------------------------------
* PRCLOSE -- the zero page back, which puts the output hook back with it
*--------------------------------------
PRCLOSE      ldx   #$00
:rest        lda   PRZP,x
             sta   $00,x
             inx
             bne   :rest
             lda   #$01                ; an echo may have painted anywhere
             sta   SCRLOST
             rts

*--- Two switches src/prnprobe.S has to settle on the real card.
*
*    PRLF  0: send a return alone and let the card or the printer's DIP
*          switch add the line feed. 1: a line feed after every return. Wrong
*          one way every line prints on top of the last; wrong the other the
*          page comes out double spaced.
*    PRHI  what the PR#1 path ORs into every byte. $80 is what BASIC sends;
*          $00 sends the byte exactly. The Pascal path ignores it.
PRLF         dfb   $00
PRHI         dfb   $80

*--- $14bf-$14e0 is keyboard.S's
             dum   $14e1
PRMODE       ds    1                   ; 0 the Pascal entry points, 1 PR#1
PRVEC        ds    2                   ; the Pascal entry being called
PRPOS        ds    2                   ; how far the walk has got
PRGAPB       ds    2                   ; GAPBEG and GAPEND, copied out of zero
PRGAPE       ds    2                   ; page before the firmware runs
             dend
