.cseg
.org 0x0000
    jmp setup
.org 0x0028
    jmp timer1_ISR


setup:
.def temp        = r16
.def msg_counter = r20
.def direction   = r23

    ; initialize hardware stack
	ldi  temp, high(RAMEND)
	out  SPH, temp
	ldi  temp, low(RAMEND)
	out  SPL, temp

    ; initialize software stack
    .equ HW_max = 256
    ldi  YH, high(RAMEND - HW_max + 1)
    ldi  YL, low(RAMEND - HW_max + 1)
    #define pushd(Rr)   st -Y, Rr
    #define popd(Rd)    ld Rd, Y+

    ; setup the timer
    call timer1_setup


main:

    ; Copy strings from program memory to data memory:

    push YL
    push YH
    push ZL
    push ZH
    ; (since parameters are passed using registers,
    ; they must be protected by caller)

    ; copy startString from program memory to data memory
    ; (startString = "*****************" defined at the end of .cseg)
    ldi  ZL, low(startString << 1)
    ldi  ZH, high(startString << 1)
    ldi  YL, low(startStringData)
    ldi  YH, high(startStringData)
    call get_message

    ; copy msg1 & 2 from program memory to data memory
    ldi  ZL, low(msg1_p << 1)
    ldi  ZH, high(msg1_p << 1)
    ldi  YL, low(line1)
    ldi  YH, high(line1)
    call get_message
    ldi  ZL, low(msg2_p << 1)
    ldi  ZH, high(msg2_p << 1)
    ldi  YL, low(line2)
    ldi  YH, high(line2)
    call get_message

    ; restore protected registers
    pop  ZH
    pop  ZL
    pop  YH
    pop  YL

    ; Then, reverse line1 to create line3
    ldi  temp, high(line1)
    push temp
    ldi  temp, low(line1)
    push temp
    ldi  temp, high(line3)
    push temp
    ldi  temp, low(line3)
    push temp
    call reverse
    pop  temp
    pop  temp
    pop  temp
    pop  temp

    ; reverse line2 to create line4
    ldi  temp, high(line2)
    push temp
    ldi  temp, low(line2)
    push temp
    ldi  temp, high(line4)
    push temp
    ldi  temp, low(line4)
    push temp
    call reverse
    pop  temp
    pop  temp
    pop  temp
    pop  temp

    ; display startString
    ldi  temp, high(startStringData)
    pushd(temp)
    ldi  temp, low(startStringData)
    pushd(temp)
    ldi  temp, high(startStringData)
    pushd(temp)
    ldi  temp, low(startStringData)
    pushd(temp)
    call display

    ; msg_counter = 0
    clr  msg_counter

    ; direction = 0
    clr  direction

    ; busy wait
done:
    rjmp done


   .equ TIMER1_DELAY = 15625     ; 1s in real time
;  .equ TIMER1_DELAY = 480       ; for simulation in Atmel Studio only
;                              
.equ TIMER1_MAX_COUNT = 0xFFFF
.equ TIMER1_COUNTER_INIT=TIMER1_MAX_COUNT-TIMER1_DELAY + 1
timer1_setup:	
    push temp

	; timer mode	
	ldi  temp, 0x00		        ; normal operation
	sts  TCCR1A, temp

	; prescale 
	; Our clock is 16 MHz, which is 16,000,000 per second
	;
	; scale values are the last 3 bits of TCCR1B:
	;
	; 000 - timer disabled
	; 001 - clock (no scaling)
	; 010 - clock / 8
	; 011 - clock / 64
	; 100 - clock / 256
	; 101 - clock / 1024
	; 110 - external pin Tx falling edge
	; 111 - external pin Tx rising edge

	ldi temp, (1<<CS12)|(1<<CS10)	; clock / 1024
	;ldi  temp, 1<<CS10	            ; clock / 1
	sts  TCCR1B, temp

	; set timer counter to TIMER1_COUNTER_INIT (defined above)
	ldi  temp, high(TIMER1_COUNTER_INIT)
	sts  TCNT1H, temp 	    ; must WRITE high byte first 
	ldi  temp, low(TIMER1_COUNTER_INIT)
	sts  TCNT1L, r16		; low byte
	
	; allow timer to interrupt the CPU when its counter overflows
	ldi  temp, 1<<TOIE1
	sts  TIMSK1, temp

    ;enable interrupts (the I bit in SREG)
	sei	

    pop temp
	ret


; timer interrupt flag is automatically
; cleared when this ISR is executed
; per page 168 ATmega datasheet
timer1_ISR:
    ; protect registers
	push r16
	push r17
	push r18
	lds  r16, SREG
	push r16

	; RESET timer counter to TIMER1_COUNTER_INIT (defined above)
	ldi  r16, high(TIMER1_COUNTER_INIT)
	sts  TCNT1H, r16 	    ; must WRITE high byte first 
	ldi  r16, low(TIMER1_COUNTER_INIT)
	sts  TCNT1L, r16		; low byte

    ; Handle the interrupt:
    ; First check direction, if it is 0 then msg_counter += 1 meaning scroll up
    ; else, msg_counter -= 1 meaning scroll down
    tst  direction
    brne scroll_down

scroll_up:
    ; msg_counter += 1 mod 4
    ; which means, whenever counter reaches 4, it resets to 0
    inc  msg_counter
    cpi  msg_counter, 4
    brne skip1
    clr  msg_counter
skip1:
    ; display(LCDCacheBottom, msg(msg_counter))
    call msg
    ; Now the low byte of msg(msg_counter) is on top of SW stack
    ; And the high byte of msg(msg_counter) is 2nd top of SW stack
    ; We can directly use it to enact display without popping and pushing back
    ; so no instruction is wasted.

;   popd(r17)
;   popd(r18)
;   pushd(r18)
;   pushd(r17)          ; This would be redundant

    ; push the other parameter for display
    ldi  r16, high(LCDCacheBottom)
    pushd(r16)
    ldi  r16, low(LCDCacheBottom)
    pushd(r16)

    call display
    rjmp next

scroll_down:
    ; msg_counter -= 1 mod 4
    ; which means, if counter < 0 after decrement, add 4 to counter
    dec  msg_counter
    brmi addBack1
    rjmp skip2
addBack1:
    subi msg_counter, -4
skip2:
    ; display(msg(msg_counter), LCDCacheTopLine)
    call msg
    popd(r17)          ; low byte of address
    popd(r18)          ; high byte of address

    ; push parameters for display
    ; remember it is the SW stack so push in reverse order
    ldi  r16, high(LCDCacheTopLine)
    pushd(r16)
    ldi  r16, low(LCDCacheTopLine)
    pushd(r16)
    pushd(r18)
    pushd(r17)
    
    call display

next:
	; interruptCount += 1
    ; if interruptCount = 10, toggle direction and clear interruptCount
    lds  r16, interruptCount
    inc  r16
    cpi  r16, 10
    brne storeBack
toggle:
    ldi  r17, 1
    eor  direction, r17
    clr  r16

    tst  direction
    breq counter_inc
    
counter_dec:
    ; if changed to scrollDown(i.e. direction = 1), msg_counter -= 1 mod 4
    dec  msg_counter
    brmi addBack2
    rjmp storeBack
addBack2:
    subi msg_counter, -4
    rjmp storeBack

counter_inc:
    ; if changed to scrollUp(i.e. direction = 0), msg_counter += 1 mod 4
    inc  msg_counter
    cpi  msg_counter, 4
    brne storeBack
    clr  msg_counter

storeBack:
    sts  interruptCount, r16

	pop  r16
	sts  SREG, r16
	pop  r18
	pop  r17
	pop  r16
	reti


display:
; display(lineA, lineB)
; Used To:     Copy two lines into the LCD cache
; Description: The parameter lineA is the address in data memory
;              of the first line, and lineB is the address in data memory
;              of the second line to be displayed.
;              Passed to the function using the software stack.
.def count = r17
.def highA = r18
.def lowA  = r19
.def highB = r21
.def lowB  = r22

    push ZL
    push ZH
    push XL
    push XH
    push temp
    push count
    push highA
    push lowA
    push highB
    push lowB

    ; pop parameters from SW stack
    popd(lowA)
    popd(highA)
    popd(lowB)
    popd(highB)

    ; is the direction 0 or 1?
    ; if 0, TopLine is printed first
    ; if 1, BottomLine is printed first
    tst  direction
    brne bottom

top:
    mov  XL, lowA
    mov  XH, highA
    ldi  ZL, low(LCDCacheTopLine)
    ldi  ZH, high(LCDCacheTopLine)

    ldi count, msg_length
top_loop:
    ld   temp, X+
    st   Z+, temp
    dec  count
    brne top_loop

    tst  direction
    brne display_done

bottom:
    mov  XL, lowB
    mov  XH, highB
    ldi  ZL, low(LCDCacheBottom)
    ldi  ZH, high(LCDCacheBottom)

    ldi count, msg_length
bottom_loop:
    ld   temp, X+
    st   Z+, temp
    dec  count
    brne bottom_loop

    tst  direction
    brne top

display_done:
    pop lowB
    pop highB
    pop lowA
    pop highA
    pop count
    pop temp
    pop XH
    pop XL
    pop ZH
    pop ZL

    .undef count
    .undef highA
    .undef lowA
    .undef highB
    .undef lowB
    ret


msg:
; msg(msg_counter)
; Used To:     Return address of line 1, 2, 3, or 4
; Description: Compute the address algebraically:
;                   address = addressOf(line1) + msg_length * msg_counter
;               msg_counter is 1: return line1's address
;                              2:        line2
;                              3:        line3
;                              0:        line4
;               Return value will be placed on the software stack.
    push temp
    push msg_counter            ; value will be changed; protect it
    push XL
    push XH                     ; will use X to load line1's addr

    tst  msg_counter            ; if msg_counter = 0, change it to 4
    brne msg_nxt2
msg_nxt1:
    ldi  msg_counter, 4
msg_nxt2:
    clr  temp                   ; use temp to calculate counter*length
msg_lp:
    dec  msg_counter
    breq msg_nxt3
    subi temp, -(msg_length)    ; subtract negative = add immediate
    rjmp msg_lp
msg_nxt3:
    ; now temp = msg_length * msg_counter
    ; load address of line1 into X
    ldi  XH, high(line1)
    ldi  XL, low(line1)
    
    ; add product to the address
    add  XL, temp
    brcc msg_nxt4               ; if no carry, move on
    inc  XH                     ; if there is a carry, add 1 to XH
msg_nxt4:
    ; place it on the software stack
    pushd(XH)
    pushd(XL)

    pop  XH
    pop  XL
    pop  msg_counter            ; restore msg_counter
    pop  temp
    ret


reverse:
; reverse(message, location)
; Used To:     Reverse Line 1 & 2, put them into Line 3 & 4
; Description: The parameter message is an address in data memory that
;              references the start of the string that will be reversed
;              and must be passed to the function on the hardware stack.
;              The parameter location is the address in data memory where
;              the reversed string will be stored.
.def count    = r17
.def end_null = r19
.equ OFFSET   = 12

    push ZL
    push ZH
    push YL
    push YH
    push XL
    push XH
    push count
    push temp
    push end_null

    in   YL, SPL
    in   YH, SPH
    
    ; Z for the address of initial string
    ldd  ZL, Y + OFFSET + 3
    ldd  ZH, Y + OFFSET + 4

    ; X for the address of reversed string
    ldd  XL, Y + OFFSET + 1
    ldd  XH, Y + OFFSET + 2
    
    ; Push the string onto the stack, counting each char.
    ; Then pop it (in reverse) into the designated address.
    clr  count
push_lp:
    ld   temp, Z+
    tst  temp
    breq do_null        ; end of string: keep the null, start to pop
    push temp           ; otherwise, push it onto the stack, repeat
    inc  count
    rjmp push_lp
do_null:
    mov  end_null, temp
pop_lp:
    pop  temp
    st   X+, temp
    dec  count
    brne pop_lp

    st   X, end_null    ; add the null at the end
    pop  end_null
    pop  temp
    pop  count
    pop  XH
    pop  XL
    pop  YH
    pop  YL
    pop  ZH
    pop  ZL

    .undef count
    .undef end_null
    ret
    

get_message:
; get_message (prog_loc, data_loc)
; Used To:    Copy msg1 and msg2 from program to data memory
; Description: The parameter prog_loc is an address in program memory
;              and must be passed to the function in registers (use Z).
;              The parameter data_loc is an address in data memory
;              and must be passed to the function in registers (use Y).
.def char = r17
    push char
get_msg_lp:
	lpm  char, Z+
    st   Y+, char
    tst  char
    brne get_msg_lp

    pop  char
    .undef char
    ret


startString: .db "*****************", 0

msg1_p: .db "Quick Brown Fox H", 0
msg2_p: .db "ops Over Lazy Dog", 0



.dseg

.equ msg_length = 18
;
; This is for the display of startup screen.
startStringData: .byte msg_length
;
; These strings contain characters to be displayed on the LCD.
line1: .byte msg_length
line2: .byte msg_length
line3: .byte msg_length
line4: .byte msg_length
;
; LCD Cache: contains a copy of the 2 lines to be displayed on the screen
LCDCacheTopLine: .byte msg_length
LCDCacheBottom:  .byte msg_length
;
; This records the number of interrupts that have happened.
; Every time it reaches 10, it toggles the variable "direction".
interruptCount: .byte 1
