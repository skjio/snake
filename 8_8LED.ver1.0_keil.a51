		ORG     0000H
        LJMP    MAIN
        
        ORG     0003H               
        RETI

        ORG     000BH               
        LJMP    T0_ISR

DATA_PORT   EQU     P0              
SCAN_PORT   EQU     P1              
BUZZER      EQU     P2.7            

VRAM_START  EQU     30H             
SCAN_IDX    EQU     38H             

SNAKE_LEN   EQU     41H             
SNAKE_DIR   EQU     42H             
MOVE_FLAG   EQU     43H             
T0_COUNT    EQU     44H             
TAIL_X      EQU     45H             
TAIL_Y      EQU     46H             
NEXT_X      EQU     47H             
NEXT_Y      EQU     48H             
FOOD_X      EQU     49H             
FOOD_Y      EQU     4AH             
SEED_X      EQU     4CH             
SEED_Y      EQU     4DH             

SNAKE_X     EQU     50H             
SNAKE_Y     EQU     60H             

MAIN:
        MOV     SP, #70H            
        SETB    BUZZER              
        
        MOV     DATA_PORT, #0FFH
        MOV     SCAN_PORT, #0FFH
        ACALL   DELAY_50MS

        MOV     SNAKE_LEN, #3       
        MOV     SNAKE_DIR, #3       
        MOV     MOVE_FLAG, #0
        MOV     T0_COUNT, #0
        MOV     SCAN_IDX, #0
        MOV     SEED_X, #17
        MOV     SEED_Y, #9

        MOV     50H, #3             
        MOV     60H, #3             
        MOV     51H, #2
        MOV     61H, #3
        MOV     52H, #1
        MOV     62H, #3

        MOV     FOOD_X, #5
        MOV     FOOD_Y, #5

        ACALL   MAP_UPDATE          

        MOV     TMOD, #01H
        MOV     TH0, #0EEH          
        MOV     TL0, #00H
        SETB    ET0
        SETB    EA                  
        SETB    TR0                 

GAME_LOOP:
        INC     SEED_X              
        MOV     A, SEED_Y
        ADD     A, #3
        MOV     SEED_Y, A

        MOV     A, MOVE_FLAG
        JZ      GAME_LOOP
        
        MOV     MOVE_FLAG, #0
        
        CLR     EA                  
        ACALL   KEY_SCAN            
        SETB    EA                  
        
        CJNE    A, #1, NOT_KEY_UP
        MOV     A, SNAKE_DIR
        CJNE    A, #1, SET_UP       
        SJMP    NOT_KEY_UP
SET_UP: 
        MOV     SNAKE_DIR, #0 
        SJMP    KEY_DONE

NOT_KEY_UP:
        CJNE    A, #9, NOT_KEY_DOWN
        MOV     A, SNAKE_DIR
        CJNE    A, #0, SET_DOWN     
        SJMP    NOT_KEY_DOWN
SET_DOWN: 
        MOV     SNAKE_DIR, #1 
        SJMP    KEY_DONE

NOT_KEY_DOWN:
        CJNE    A, #4, NOT_KEY_LEFT
        MOV     A, SNAKE_DIR
        CJNE    A, #3, SET_LEFT     
        SJMP    NOT_KEY_LEFT
SET_LEFT: 
        MOV     SNAKE_DIR, #2 
        SJMP    KEY_DONE

NOT_KEY_LEFT:
        CJNE    A, #6, KEY_DONE
        MOV     A, SNAKE_DIR
        CJNE    A, #2, SET_RIGHT    
        SJMP    KEY_DONE
SET_RIGHT: 
        MOV     SNAKE_DIR, #3

KEY_DONE:
        ACALL   UPDATE_SNAKE        
        ACALL   MAP_UPDATE          
        LJMP    GAME_LOOP

T0_ISR:
        PUSH    ACC
        PUSH    PSW

        MOV     TH0, #0EEH          
        MOV     TL0, #00H

        INC     T0_COUNT
        MOV     A, T0_COUNT
        CJNE    A, #100, DO_SCAN
        MOV     T0_COUNT, #0
        MOV     MOVE_FLAG, #1       

DO_SCAN:
        MOV     SCAN_PORT, #0FFH    

        MOV     A, #VRAM_START
        ADD     A, SCAN_IDX
        MOV     R0, A
        MOV     A, @R0
        MOV     DATA_PORT, A        

        MOV     A, SCAN_IDX
        ACALL   GET_SCAN_CODE
        MOV     SCAN_PORT, A        

        INC     SCAN_IDX
        MOV     A, SCAN_IDX
        CJNE    A, #8, T0_EXIT
        MOV     SCAN_IDX, #0

T0_EXIT:
        POP     PSW
        POP     ACC
        RETI

GET_SCAN_CODE:
        INC     A
        MOVC    A, @A+PC
        RET
        DB      0FEH, 0FDH, 0FBH, 0F7H, 0EFH, 0DFH, 0BFH, 07FH

UPDATE_SNAKE:
        MOV     A, SNAKE_DIR
        CJNE    A, #0, CHK_DN
        LJMP    MOVE_X_INC          
CHK_DN:
        CJNE    A, #1, CHK_LF
        LJMP    MOVE_X_DEC          
CHK_LF:
        CJNE    A, #2, CHK_RT
        LJMP    MOVE_Y_DEC          
CHK_RT:
        LJMP    MOVE_Y_INC          

MOVE_Y_DEC:
        MOV     A, 60H              
        JNZ     Y_OK1
        LJMP    GAME_OVER_TRIGGER
Y_OK1:  
        DEC     A 
        MOV     NEXT_Y, A 
        MOV     NEXT_X, 50H         
        LJMP    CHK_SELF

MOVE_Y_INC:
        MOV     A, 60H
        INC     A
        CJNE    A, #8, Y_OK2
        LJMP    GAME_OVER_TRIGGER
Y_OK2:  
        MOV     NEXT_Y, A 
        MOV     NEXT_X, 50H
        LJMP    CHK_SELF

MOVE_X_DEC:
        MOV     A, 50H
        JNZ     X_OK1
        LJMP    GAME_OVER_TRIGGER
X_OK1:  
        DEC     A 
        MOV     NEXT_X, A 
        MOV     NEXT_Y, 60H 
        LJMP    CHK_SELF

MOVE_X_INC:
        MOV     A, 50H
        INC     A
        CJNE    A, #8, X_OK2
        LJMP    GAME_OVER_TRIGGER
X_OK2:  
        MOV     NEXT_X, A 
        MOV     NEXT_Y, 60H

CHK_SELF:
        MOV     A, SNAKE_LEN
        DEC     A
        MOV     R0, A
        MOV     R2, #1
SELF_LP:
        MOV     A, R0
        CLR     C
        SUBB    A, R2
        JC      CHK_FOOD
        
        MOV     A, R2 
        ADD     A, #50H             
        MOV     R1, A 
        MOV     A, @R1
        CJNE    A, NEXT_X, NEXT_N
        
        MOV     A, R2 
        ADD     A, #60H             
        MOV     R1, A 
        MOV     A, @R1
        CJNE    A, NEXT_Y, NEXT_N
        LJMP    GAME_OVER_TRIGGER
NEXT_N: 
        INC     R2 
        SJMP    SELF_LP

CHK_FOOD:
        MOV     A, NEXT_X 
        CJNE    A, FOOD_X, NO_EAT
        MOV     A, NEXT_Y 
        CJNE    A, FOOD_Y, NO_EAT
        INC     SNAKE_LEN
        ACALL   GENERATE_FOOD
        SJMP    SHIFT_BODY
NO_EAT:
        MOV     A, SNAKE_LEN 
        DEC     A 
        MOV     R0, A
        
        MOV     A, R0 
        ADD     A, #50H 
        MOV     R1, A 
        MOV     TAIL_X, @R1
        
        MOV     A, R0 
        ADD     A, #60H 
        MOV     R1, A 
        MOV     TAIL_Y, @R1

SHIFT_BODY:
        MOV     A, SNAKE_LEN 
        DEC     A 
        MOV     R0, A
S_LP:   
        MOV     A, R0 
        JZ      S_DN
        DEC     R0
        
        MOV     A, R0 
        ADD     A, #50H 
        MOV     R1, A 
        MOV     A, @R1 
        INC     R0
        PUSH    ACC
        MOV     A, R0 
        ADD     A, #50H 
        MOV     R1, A 
        POP     ACC 
        MOV     @R1, A
        
        DEC     R0
        MOV     A, R0 
        ADD     A, #60H 
        MOV     R1, A 
        MOV     A, @R1 
        INC     R0
        PUSH    ACC
        MOV     A, R0 
        ADD     A, #60H 
        MOV     R1, A 
        POP     ACC 
        MOV     @R1, A
        
        DEC     R0 
        SJMP    S_LP
S_DN:   
        MOV     50H, NEXT_X 
        MOV     60H, NEXT_Y
        RET

GAME_OVER_TRIGGER:
        CLR     TR0                 
        MOV     SCAN_PORT, #0FFH    
        CLR     BUZZER              
        ACALL   DELAY_50MS
        SETB    BUZZER
DIE_LOOP:    
        SJMP    DIE_LOOP

GENERATE_FOOD:
        MOV     A, SEED_X 
        ANL     A, #07H 
        MOV     FOOD_X, A
        
        MOV     A, SEED_Y 
        ANL     A, #07H 
        MOV     FOOD_Y, A
        RET

MAP_UPDATE:
        MOV     R0, #VRAM_START 
        MOV     R7, #8
CLR_V:  
        MOV     @R0, #11111111B 
        INC     R0 
        DJNZ    R7, CLR_V  

        MOV     A, #VRAM_START 
        ADD     A, FOOD_Y 
        MOV     R0, A
        MOV     A, #0FEH 
        MOV     R2, FOOD_X 
        JZ      F_OK
F_LP:   
        RL      A 
        DJNZ    R2, F_LP
F_OK:   
        MOV     R6, A 
        MOV     A, @R0 
        ANL     A, R6 
        MOV     @R0, A

        MOV     R3, #0
S_R_LP: 
        MOV     A, R3 
        ADD     A, #50H             
        MOV     R0, A 
        MOV     A, @R0              ; ?? 修正：間接定址必須先讀進 A
        MOV     R4, A               ; ?? 修正：再由 A 存入 R4
        
        MOV     A, R3 
        ADD     A, #60H             
        MOV     R0, A 
        MOV     A, @R0              ; ?? 修正：間接定址必須先讀進 A
        MOV     R5, A               ; ?? 修正：再由 A 存入 R5
        
        MOV     A, #VRAM_START 
        ADD     A, R5 
        MOV     R0, A
        MOV     A, #0FEH 
        
        PUSH    ACC                 ; 先保護當前 A 裡面的 0FEH
        MOV     A, R4               ; ?? 修正：利用 A 來中轉 R4 暫存器
        MOV     R2, A               ; ?? 修正：將值傳給 R2 (等同於 MOV R2, R4)
        POP     ACC                 ; 還原 A 裡面的 0FEH
        
        JZ      S_OK
S_LP_B: 
        RL      A 
        DJNZ    R2, S_LP_B
S_OK:   
        MOV     R6, A 
        MOV     A, @R0 
        ANL     A, R6 
        MOV     @R0, A
        
        INC     R3 
        MOV     A, R3 
        CJNE    A, SNAKE_LEN, S_R_LP
        RET

KEY_SCAN:
        MOV     DATA_PORT, #0FFH
        MOV     SCAN_PORT, #0FFH

        CLR     P1.0 
        SETB    P1.1 
        SETB    P1.2 
        SETB    P1.3
        MOV     A, P2 
        ANL     A, #0FH 
        CJNE    A, #0FH, R0_H

        SETB    P1.0 
        CLR     P1.1 
        SETB    P1.2 
        SETB    P1.3
        MOV     A, P2 
        ANL     A, #0FH 
        CJNE    A, #0FH, R1_H

        SETB    P1.0 
        SETB    P1.1 
        CLR     P1.2 
        SETB    P1.3
        MOV     A, P2 
        ANL     A, #0FH 
        CJNE    A, #0FH, R2_H

        SETB    P1.0 
        SETB    P1.1 
        SETB    P1.2 
        CLR     P1.3
        MOV     A, P2 
        ANL     A, #0FH 
        CJNE    A, #0FH, R3_H

        MOV     A, #0FFH 
        RET
R0_H:   
        MOV     R2, #0 
        SJMP    DEC_C
R1_H:   
        MOV     R2, #4 
        SJMP    DEC_C
R2_H:   
        MOV     R2, #8 
        SJMP    DEC_C
R3_H:   
        MOV     R2, #12

DEC_C:
        JB      ACC.0, N_C0 
        MOV     A, #0 
        ADD     A, R2 
        RET
N_C0:   
        JB      ACC.1, N_C1 
        MOV     A, #1 
        ADD     A, R2 
        RET
N_C1:   
        JB      ACC.2, N_C2 
        MOV     A, #2 
        ADD     A, R2 
        RET
N_C2:   
        JB      ACC.3, K_ER 
        MOV     A, #3 
        ADD     A, R2 
        RET
K_ER:   
        MOV     A, #0FFH 
        RET

DELAY_50MS:
        MOV     R4, #250
D50_1:  MOV     R3, #100
        DJNZ    R3, $
        DJNZ    R4, D50_1
        RET

        END