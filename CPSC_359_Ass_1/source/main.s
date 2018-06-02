/****************************************************
 * Assignment 1, CPSC 359
 * SNES device driver
 * Glenn Skelton, 10041868
 *
 ****************************************************/

.sect	.data

author:
	.asciz	"Created by: Glenn Skelton\n\n"
prompt:
	.asciz	"Please press a button...\n\n"
response:
	.asciz	"You have pressed "
terminate:
	.asciz	"Program is terminating...\n"

btn_y:
	.asciz	"Y\n\n"
btn_x:
	.asciz	"X\n\n"
btn_a:
	.asciz	"A\n\n"
btn_b:
	.asciz	"B\n\n"
select:
	.asciz	"SELECT\n\n"
up:
	.asciz	"Joy-pad UP\n\n"
down:
	.asciz	"Joy-pad DOWN\n\n"
left:
	.asciz	"Joy-pad LEFT\n\n"
right:
	.asciz	"Joy-pad RIGHT\n\n"
lBumper:
	.asciz	"LEFT BUMPER\n\n"
rBumper:
	.asciz	"RIGHT BUMPER\n\n"

GpioPtr:
	.int	0

/*--------------------- CODE ------------------------*/

.sect	.text
.global	main

/*****************************************************
 * Purpose: To prompt a user for input using a snes
 * controller. Based on the button pressed, the 
 * program will inform the user which button has been 
 * pressed.
 * 
 *****************************************************/
main:

	@ setup pins
	ldr	r0, =GpioPtr			@ get address of pointer to initialize
	bl	initGpioPtr			@ set up base address

	mov	r0, #1				@ set for output in r1
	mov	r1, #9				@ pin 9 in r1 (Latch)
	bl	init_GPIO			@ set pin 9 to output

	mov	r0, #1				@ set for output in r1
	mov	r1, #11				@ pin 11 in r1 (Clock)
	bl	init_GPIO			@ set pin 11 to output

	mov	r0, #0				@ set for input in r1
	mov	r1, #10				@ pin 10 in r1 (Data)
	bl	init_GPIO			@ set pin 10 to input

	@ print beginning message
	ldr	r0, =author			@ get the address for the author message to print
	bl	printf				@ print the author message


	@ main program loop			
	ldr	r0, =prompt			@ get address for string to print
	bl	printf				@ prompt user for input
	
readInLoop:
	bl	Read_SNES			@ get the input from the SNES paddle
	mov	r1, #0xFFFF			@ mask to check if a button was pushed or not
	teq	r0, r1				@ test to see if a button was pushed
	beq	readInLoop			@ if not go back and wait until it one is pushed
	
@ sometimes prints multiple times in a row, Don't know why *************************************************************************8

btnPressed:
	@ r0 contains the buttons pressed
	mov	r4, r0				@ store the button values in r4	

	@ determine from bits in r0 what was pressed and print the message stdout
	mov	r1, #0xFFF7			@ move test mask to see if start was pressed
	teq	r4, r1				@ test to see if user pressed start
	beq	end				@ if so, terminate program
	
	ldr	r0, =response			@ get the response message
	bl	printf				@ print the response to stdout
	
	@ call printBtn to determine what button was pressed
	mov	r0, r4				@ put button bits into argument r0 for printBtn
	bl	printBtn			@ call printBtn to determine the button pressed

	ldr	r0, =prompt			@ get address for string to print
	bl	printf				@ prompt user for input
	
readOutLoop:
	@ delay to eliminate any accidental multiple prints
	mov	r0, #5000			@ value to delay, multiplied by 2
	lsl 	r0, #1				@ delay is 10 miliseconds
	bl	delayMicroseconds		@ delay for 10 miliseconds

	bl	Read_SNES			@ get the input from the SNES paddle
	mov	r1, #0xFFFF			@ mask to check if a button was released
	cmp	r0, r1				@ test to see if a button was pushed	
	bne	readOutLoop			@ if not go back and wait until it one is pushed
	
	bal	readInLoop
	
	

end:
	ldr	r0, =terminate			@ get address for terminating message
	bl	printf				@ print terminating message
	bl	exit


/*------------------- FUNCTIONS ---------------------*/

/*****************************************************
 * Purpose: To set a pins function either input or 
 * output.
 * Pre: The GPIO address is valid.
 * Post: The pins function bits will be set according 
 * to the value passed in.
 * Param: r0 - the function value to set (output/input)
 * r1 - the pin number to be set
 * Return: None
 *****************************************************/
init_GPIO:
	push	{r4, r5, r7, lr}

	func	.req	r0
	pin	.req	r1
	gPtr	.req	r2
	addr	.req	r3
	mask	.req	r4
	temp	.req	r5
	cnt	.req	r7	

	ldr	gPtr, =GpioPtr			@ get the base address
	ldr	addr, [gPtr]			@ read the value of the base address

	mov	cnt, #0				@ initialize counter to 0 for loop
setFuncLoop:
	cmp	pin, #9				@ check to see if pin <= 9
	subhi	pin, #10			@ subtract 10 if not <= 9
	addhi	addr, #4			@ increment GPIO base address
	bhi	setFuncLoop			@ if pin value not <= 9 branch

	add	pin, pin, lsl #1		@ multiply pin value by 3
	lsl	func, pin			@ move the function value over to the pin bits
	mov	mask, #7			@ store mask
	lsl	mask, pin			@ move the mask #7 to the pin bits			

	ldr	temp, [addr]			@ store the effective address in temp	
	bic	temp, mask	 		@ clear the pin function
	orr	temp, func			@ set the pin function
	str	temp, [addr]			@ store the value of function back into GPIO

	.unreq	func
	.unreq	pin
	.unreq	gPtr
	.unreq	addr
	.unreq	mask
	.unreq	temp
	.unreq	cnt

	pop	{r4, r5, r7, lr}

	bx	lr				@ return to calling function

/******************************************************
 * Purpose: To read in the state of the controller for 
 * one register cycle (16 clock cycles) and return the
 * corresponding bit pattern transfered from the 
 * controller.
 * Pre: The pins functions are set.
 * Post: The bit pattern for which buttons are pressed
 * is recorded in a register and returned.
 * Param: None
 * Return: a register containing all 16 bits passed from
 * the controller to the core in the proper ordering.
 ******************************************************/
Read_SNES:
	push	{r4, r5, lr}

	cnt	.req	r4
	btns	.req	r5

	mov	btns, #0			@ register to store button samples
	
	mov	r0, #1				@ store 1 for function call to set clock
	bl	Write_Clock			@ set clock line
	mov	r0, #1				@ store 1 for function call to set latch
	bl	Write_Latch			@ set latch line
	
	mov	r0, #12				@ store value of 12 microseconds for delay
	bl	delayMicroseconds		@ delay 12 microseconds
	mov	r0, #0				@ store 0 for clearing latch line
	bl	Write_Latch			@ clear latch line
	
	mov	cnt, #0				@ loop counter set to 0
readLoop: 
	mov	r0, #6				@ store value of 6 microseconds for delay
	bl	delayMicroseconds		@ delay 6 microseconds
	
	mov	r0, #0				@ store 0 for function call to clear clock
	bl	Write_Clock			@ clear clock line

	mov	r0, #6				@ store value of 6 microseconds for delay
	bl	delayMicroseconds		@ delay 6 microseconds

	bl	Read_Data			@ read the input from the serial data
	orr	btns, r0			@ store the bit read in in r7
	ror	btns, #1			@ rotate one bit right to be ready to store next
	
	mov	r0, #1				@ store 1 for function call to set clock
	bl	Write_Clock			@ set clock line
	
	add	cnt, #1				@ increment the loop counter
	cmp	cnt, #16			@ check to see if r1 is 16 yet
	bne	readLoop			@ if loop counter is not 16, branch through loop again

readEnd:	
	mov	r0, btns			@ move the word containing the input into r0 for return
	lsr	r0, #16				@ move all bits over into the lower half of the word
	
	.unreq	btns
	.unreq	cnt	

	pop	{r4, r5, lr}	
	bx	lr				@ return to calling function

/******************************************************
 * Purpose: To turn the latch line on or off.
 * Pre: The latches function is set to output.
 * Post: The latches voltage is changed accordingly.
 * Param: r0 - the value to write to the line
 * Return: None
 ******************************************************/
Write_Latch:
	push	{lr}			

	val	.req	r0
	gPtr	.req	r1
	mask	.req	r2

	ldr	gPtr, =GpioPtr			@ get the base address
	ldr	gPtr, [gPtr]			@ get the value of the base address
					
	mov	mask, #1			@ set the mask and store in r2
	lsl	mask, #9			@ pin number to change
	
	teq	val, #0				@ test to see whether to clear or store
	streq	mask, [gPtr, #0x28]		@ if r0 is 0, clear
	strne	mask, [gPtr, #0x1C]		@ if r0 is 1, set

	.unreq	val
	.unreq	gPtr
	.unreq	mask

	pop	{lr}		
	bx	lr				@ return to calling function


/******************************************************
 * Purpose: To turn the clock line on or off.
 * Pre: The clocks function is set to output.
 * Post: The clocks voltage is changed accordingly.
 * Param: r0 - the value to write to the line
 * Return: None
 ******************************************************/
Write_Clock:
	push	{lr}		
	
	val	.req	r0
	gPtr	.req	r1
	mask	.req	r2

	ldr	gPtr, =GpioPtr			@ get the base address
	ldr	gPtr, [gPtr]			@ get the value of the base address
					
	mov	mask, #1			@ set the mask and store in r2
	lsl	mask, #11			@ pin number to change
	
	teq	val, #0				@ test to see whether to clear or store
	streq	mask, [gPtr, #0x28]		@ if r0 is 0, clear
	strne	mask, [gPtr, #0x1C]		@ if r0 is 1, set

	.unreq	val
	.unreq	gPtr
	.unreq	mask

	pop	{lr}		
	bx	lr				@ return to calling function

/******************************************************
 * Purpose: To read the input from the snes controller.
 * Pre: The data lines function is set to input.
 * Post: The value is recorded from the line.
 * Param: None
 * Return: The bit value read in from the data line.
 ******************************************************/
Read_Data:
	push	{lr}		

	val	.req	r0
	addr	.req	r1
	gPtr	.req	r2
	mask	.req	r3
	
	mov	val, #10			@ pin number 10 for reading Data			
	ldr	gPtr, =GpioPtr			@ get the base address for GPIO
	ldr	gPtr, [gPtr]			@ get the value of the base pointer and store
	ldr	addr, [gPtr, #52]		@ get the effective address for reading
	
	mov	mask, #1			@ set bit mask				
	lsl	mask, val			@ move the value into the pin bit
	and	addr, mask			@ test to get the value of the bit in r1
	teq	addr, #0			@ test to see if it is 0 or 1
	
	moveq	val, #0				@ return 0 if 0
	movne	val, #1				@ return 1 if 1

	.unreq	val
	.unreq	addr
	.unreq	gPtr
	.unreq	mask

	pop	{lr}				
	bx	lr				@ return to calling function

/******************************************************
 * Purpose: To print out the button message based on 
 * which bit pattern is passed in.
 * Pre: The snes recorded a valid bit pattern.
 * Post: The appropriate message is printed out.
 * Param: r0 - the bit pattern recorded from the snes 
 * controller.
 * Return: None 
 ******************************************************/
printBtn:
	push	{lr}

	val	.req	r1
	btn	.req	r2
		
	mov	val, r0

	mov	btn, #0xFFFE
	teq	val, btn
	ldreq	r0, =btn_b
	bleq	printf
	beq	endPrintBtn
	
	mov	btn, #0xFFFD
	teq	val, btn
	ldreq	r0, =btn_y
	bleq	printf
	beq	endPrintBtn

	mov	btn, #0xFFFB
	teq	val, btn
	ldreq	r0, =select
	bleq	printf
	beq	endPrintBtn

	mov	btn, #0xFFEF
	teq	val, btn
	ldreq	r0, =up
	bleq	printf
	beq	endPrintBtn

	mov	btn, #0xFFDF
	teq	val, btn
	ldreq	r0, =down
	bleq	printf
	beq	endPrintBtn
	
	mov	btn, #0xFFBF
	teq	val, btn
	ldreq	r0, =left
	bleq	printf
	beq	endPrintBtn

	mov	btn, #0xFF7F
	teq	val, btn
	ldreq	r0, =right
	bleq	printf
	beq	endPrintBtn

	mov	btn, #0xFEFF
	teq	val, btn
	ldreq	r0, =btn_a
	bleq	printf
	beq	endPrintBtn

	mov	btn, #0xFDFF
	teq	val, btn
	ldreq	r0, =btn_x
	bleq	printf
	beq	endPrintBtn
	
	mov	btn, #0xFBFF
	teq	val, btn
	ldreq	r0, =lBumper
	bleq	printf
	beq	endPrintBtn

	mov	btn, #0xF7FF
	teq	val, btn
	ldreq	r0, =rBumper
	bleq	printf
	beq	endPrintBtn

endPrintBtn:
	.unreq	val
	.unreq	btn

	pop	{lr}
	bx	lr

.end

