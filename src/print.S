*--------------------------------------
* PRINT.S -- the document on a parallel printer in slot 1 (OA-P, Esc Ctrl-P)
*
* Written against an Epson FX-80 on a parallel card in slot 1, which is the
* machine it was asked for. Anything that takes the FX-80's escape codes will
* do; anything in slot 1 that is not a printer card is refused before it is
* called, as far as that can be told -- see PRFIND.
*
* WHAT GOES ON THE PAPER IS WHAT IS ON THE SCREEN, LINE FOR LINE. Saving puts
* only the writer's own returns in the file and leaves the wrapping to whoever
* reads it. A printer is not a reader that wraps, and the editor already laid
* every line out against a margin at column 76 -- inside the FX-80's 80 -- so
* every break in the buffer, all three kinds, becomes a return here.
*
* THE MARKDOWN IS PRINTED, NOT SHOWN. **bold** and __bold__ print emphasized,
* *italic* and _italic_ in italics, `code` double-struck, and a line opening
* with #s and a space prints wide and emphasized -- each marker swapped for the
* FX-80's own code and left off the paper. So a line comes out shorter than it
* stood on the screen, never longer, and the breaks still fall where they did.
* The rules are a small, safe subset of CommonMark's, in PRTEXT. Whatever they
* do not recognise as markup prints as typed, so the worst a stray asterisk can
* do is appear. Emphasis ends with its paragraph at the latest, so one left
* open cannot run on through the document; code does not, because a fence
* spans paragraphs.
*
* NEWPRINT, a printer emulator, draws all of this with Printer set to FX-80
* and Format to Graphics. Its Document format draws bold and italics and drops
* the wide codes; its ASCII format acts on no codes at all, and shows the
* printable half of each.
*
* BIT 7. Everything in the buffer is high ASCII, and an FX-80 prints $80-$FF
* in italics. The Pascal path sends every byte with bit 7 clear. The PR#1
* path sends it as PRHI says: set, by default, the way BASIC sends it, which
* leaves the stripping to the card's firmware as PR#1 from BASIC always has.
* A Grappler+-style card feeding NEWPRINT was seen to need exactly that: sent
* with bit 7 clear, it put a space after most control bytes, which split
* every ESC from its command. Sent set, it strips the bit and passes the
* codes through clean -- until it is sent a DC4, after which it passes bit 7
* through too and the rest of the page came out missing or in italics. So
* PRHI stays $80, and the DC4 is never sent; see below.
*
* CONTROL CODES ARE NOT SAFE EITHER. Card firmware reads some of them as
* commands to itself -- that DC4 is one, and a Grappler's Ctrl-I is another --
* so nothing here sends a bare control code but CR, LF, FF and the parameter
* after an ESC. Wide headings use ESC W, not SO and DC4.
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
PRITAL       equ   $01                 ; PRSTY: what the markup has open
PRBOLD       equ   $02
PRCODE       equ   $04
PRHEAD       equ   $08
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

*--- A DEL first, which a printer takes as "rub out the last character" and
*    so, with nothing on the line yet, as nothing. A Grappler+ slips a space
*    in after the first byte it sends after the Apple boots, and that space,
*    between ESC and @, made the reset a stray "@" at the top of the page.
*    After a DEL it is only a space, ahead of the reset. A NUL does not do:
*    the card does not count it as the first byte.
             lda   #$7f
             jsr   PROUT

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
             sta   PRSTY               ; no emphasis open
             lda   #BUFLO
             sta   PRPOS+1
             jsr   PRLINE              ; the document opens on a fresh line

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
             jsr   PRBRK
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

:text        jsr   PRTEXT              ; markup becomes codes; carry set
             bcc   :next               ; means print it as typed
             and   #$7f
             jsr   PROUT
:next        inc   PRPOS
             bne   :loop
             inc   PRPOS+1
             jmp   :loop

:end         lda   #HARDCR             ; a last line with no return of its
             jsr   PRBRK               ; own, and anything left open closed
             jsr   PRNL
             lda   #$0c                ; form feed: the page out of the printer
             jsr   PROUT
             jsr   PRCLOSE
             jmp   RESTORESTAT         ; the busy notice was the feedback

*--------------------------------------
* PRTEXT -- one text byte, in A, from the walk at PRPOS. Carry clear: it was
*           markup, and has been dealt with. Carry set: print A as it is.
*           A marker that takes its partner with it moves PRPOS onto the
*           partner, and the walk steps past.
*--------------------------------------
PRTEXT       sta   PRCH
             cmp   #BACKTICK           ; code: everything inside it as typed
             bne   :notcode
             lda   PRSTY
             eor   #PRCODE
             sta   PRSTY
             and   #PRCODE
             beq   :codeoff
             lda   #'G'                ; double-strike on
             bne   :code
:codeoff     lda   #'H'                ; and off
:code        jsr   PRESC2
             jmp   :eaten

:notcode     lda   PRSTY
             and   #PRCODE
             bne   :lit
             lda   PRCH
             cmp   #$aa                ; *
             beq   :mark
             cmp   #$df                ; _
             beq   :mark
             cmp   #$a3                ; #, which only counts first on a line
             bne   :lit
             lda   PRBOL
             beq   :lit
             jsr   PRHASH
             bcs   :lit
             bcc   :eaten
:mark        jsr   PRMARK
             bcs   :lit

:eaten       jsr   :seen
             clc
             rts
:lit         jsr   :seen
             lda   PRCH
             sec
             rts
:seen        lda   PRCH                ; what the next marker looks back at
             sta   PRLAST
             lda   #$00
             sta   PRBOL
             rts

*--------------------------------------
* PRMARK -- an * or _ at PRPOS, and in PRCH. Doubled it is bold, single it is
*           italic. It opens if nothing of its kind is open and the next
*           character is not a space or a break; it closes if one is open and
*           the last character was not a space. An _ also has to stand at the
*           edge of a word, so snake_case is left alone. Anything else is not
*           markup, and carry comes back set.
*--------------------------------------
PRMARK       lda   #$00                ; no partner yet
             sta   PRSKIP+1
             jsr   PRPEEK0             ; the character after it
             cmp   PRCH
             bne   :single
             lda   PRPK                ; doubled: the partner is there
             sta   PRSKIP
             lda   PRPK+1
             sta   PRSKIP+1
             jsr   PRADV
             jsr   PRGET
             sta   PRNXT
             lda   PRSTY               ; a heading is emphasized already: the
             and   #PRHEAD             ; pair is only dropped
             bne   :skip
             lda   #PRBOLD
             bne   :which
:single      sta   PRNXT
             lda   #PRITAL
:which       sta   PRFLG
             and   PRSTY
             beq   :open

             lda   PRLAST              ; closing, after a space? not markup
             cmp   #TEXTLO+1
             bcc   :lit
             lda   PRCH
             cmp   #$df
             bne   :close
             lda   PRNXT               ; _ closing inside a word
             jsr   PRWORD
             bcs   :lit
:close       lda   PRSTY
             eor   PRFLG
             sta   PRSTY
             lda   PRFLG
             cmp   #PRBOLD
             beq   :boff
             lda   #'5'                ; italic off
             bne   :send
:boff        lda   #'F'                ; emphasized off
             bne   :send

:open        lda   PRNXT               ; opening before a space or a break?
             cmp   #TEXTLO+1
             bcc   :lit
             lda   PRCH
             cmp   #$df
             bne   :on
             lda   PRLAST              ; _ opening inside a word
             jsr   PRWORD
             bcs   :lit
:on          lda   PRSTY
             ora   PRFLG
             sta   PRSTY
             lda   PRFLG
             cmp   #PRBOLD
             beq   :bon
             lda   #'4'                ; italic on
             bne   :send
:bon         lda   #'E'                ; emphasized on
:send        jsr   PRESC2
:skip        lda   PRSKIP+1            ; a partner to step over? No buffer
             beq   :done               ; position is in page zero
             sta   PRPOS+1
             lda   PRSKIP
             sta   PRPOS
:done        clc
             rts
:lit         sec
             rts

*--------------------------------------
* PRHASH -- a # first on its line. One or more, then a space, is a heading:
*           wide to the end of the line and emphasized, and the #s and the
*           space are left off. Carry set if it is not one.
*--------------------------------------
PRHASH       jsr   PRPEEK0
:more        cmp   #$a3
             bne   :end
             jsr   PRADV
             jsr   PRGET
             jmp   :more
:end         cmp   #$a0
             bne   :no
             lda   PRPK                ; the walk goes on after the space
             sta   PRPOS
             lda   PRPK+1
             sta   PRPOS+1
             lda   #'W'                ; wide on: ESC W with a binary 1,
             jsr   PRESC2              ; which NEWPRINT's Document format
             lda   #$01                ; drops unseen where an ASCII '1'
             jsr   PROUT               ; would print
             lda   #'E'
             jsr   PRESC2
             lda   PRSTY
             ora   #PRHEAD
             sta   PRSTY
             clc
             rts
:no          sec
             rts

*--------------------------------------
* PRBRK -- a break, in A, is about to be printed. A heading ends with its line
*          and emphasis with its paragraph, whatever the markup said.
*--------------------------------------
PRBRK        cmp   #HARDCR
             bne   :head
             lda   PRSTY
             and   #PRITAL
             beq   :bold
             lda   #'5'
             jsr   PRESC2
:bold        lda   PRSTY
             and   #PRBOLD
             beq   :para
             lda   #'F'
             jsr   PRESC2
:para        lda   PRSTY
             and   #PRCODE+PRHEAD      ; code runs on: a fence spans paragraphs
             sta   PRSTY
:head        lda   PRSTY
             and   #PRHEAD
             beq   PRLINE
             lda   PRSTY
             and   #$ff-PRHEAD-PRBOLD  ; the heading's emphasis, and any **
             sta   PRSTY               ; inside it, end together
             lda   #'W'                ; wide off
             jsr   PRESC2
             lda   #$00
             jsr   PROUT
             lda   #'F'
             jsr   PRESC2
PRLINE       lda   #$a0                ; a line starts as if after a space
             sta   PRLAST
             lda   #$01
             sta   PRBOL
             rts

*--------------------------------------
* PRPEEK0 -- the character after PRPOS, with PRPK left on it
* PRADV   -- PRPK on to the next character, over the gap
* PRGET   -- the character at PRPK; a return past the end of the buffer
*--------------------------------------
PRPEEK0      lda   PRPOS
             sta   PRPK
             lda   PRPOS+1
             sta   PRPK+1
             jsr   PRADV
PRGET        lda   PRPK+1
             cmp   #BUFHI
             bcc   :read
             lda   #HARDCR
             rts
:read        sta   AUXPTR+1            ; the walk puts AUXPTR back for itself
             lda   PRPK
             sta   AUXPTR
             ldy   #$00
             jmp   AUXRD

PRADV        inc   PRPK
             bne   :gap
             inc   PRPK+1
:gap         lda   PRPK
             cmp   PRGAPB
             bne   :done
             lda   PRPK+1
             cmp   PRGAPB+1
             bne   :done
             lda   PRGAPE
             sta   PRPK
             lda   PRGAPE+1
             sta   PRPK+1
:done        rts

*--------------------------------------
* PRWORD -- carry set if A is a letter or a digit
*--------------------------------------
PRWORD       cmp   #$b0
             bcc   :no
             cmp   #$ba
             bcc   :yes
             and   #$df                ; lower case folded onto upper
             cmp   #$c1
             bcc   :no
             cmp   #$db
             bcs   :no
:yes         sec
             rts
:no          clc
             rts

*--------------------------------------
* PRESC2 -- ESC and then the byte in A
*--------------------------------------
PRESC2       pha
             lda   #PRESC
             jsr   PROUT
             pla
             jmp   PROUT

*--------------------------------------
* PRFIND -- what is in slot 1? Carry clear and PRMODE set if it can be driven.
*
* With no Pascal signature the only way in is to jump into the ROM, so
* something had better be there. An empty slot reads the floating bus --
* whatever video byte the hardware fetched that cycle, which drifts between
* reads -- while a ROM reads the same every time. A blank screen is the trap:
* it floats as $A0 over and over, which is steady too, so a page of one
* repeated byte does not count.
*
* Only the first 64 bytes are looked at. A card's ROM need not fill its page:
* on an Epson APL card $C1C0-$C1FF floats, and a whole-page check refused it.
* The entry PR#1 jumps into is at the start, and that is what has to be there.
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
             cpx   #$40                ; the first 64 bytes only: see above
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
             cpx   #$40                ; the first 64 bytes only: see above
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

*--- Two switches, settled by src/prnprobe.S on a Grappler+ feeding NEWPRINT.
*
*    PRLF  0: send a return alone and let the card or the printer's DIP
*          switch add the line feed. 1: a line feed after every return. Wrong
*          one way every line prints on top of the last; wrong the other the
*          page comes out double spaced.
*    PRHI  what the PR#1 path ORs into every byte. $80 is what BASIC sends,
*          and trusts the card to strip it; $00 sends the byte exactly. The
*          Pascal path ignores it.
PRLF         dfb   $00
PRHI         dfb   $80

*--- $14bf-$14e0 is keyboard.S's
             dum   $14e1
PRMODE       ds    1                   ; 0 the Pascal entry points, 1 PR#1
PRVEC        ds    2                   ; the Pascal entry being called
PRPOS        ds    2                   ; how far the walk has got
PRGAPB       ds    2                   ; GAPBEG and GAPEND, copied out of zero
PRGAPE       ds    2                   ; page before the firmware runs
PRSTY        ds    1                   ; what is open: PRITAL PRBOLD PRCODE
                                       ; PRHEAD
PRCH         ds    1                   ; the character PRTEXT was given
PRLAST       ds    1                   ; and the one before it
PRBOL        ds    1                   ; nonzero: nothing yet on this line
PRNXT        ds    1                   ; the character after a marker
PRFLG        ds    1                   ; the one PRSTY bit a marker would flip
PRPK         ds    2                   ; where the look ahead has got
PRSKIP       ds    2                   ; a doubled marker's partner, or 0
             dend                      ; ends at $14f3; $1500 is PRZP
