module IdrisJvm.Core.Operator

import IdrisJvm.Core.Asm
import IdrisJvm.Core.Common
import IdrisJvm.Core.Foreign
import IdrisJvm.IR.Types

%access public export

binaryOp : InferredType -> (InferredType -> Asm ()) -> Asm () -> LVar -> LVar -> Asm ()
binaryOp ty ret ops l r = do
  locTypes <- GetFunctionLocTypes
  let lTy = getLocTy locTypes l
  let rTy = getLocTy locTypes r
  loadVar locTypes lTy ty l
  loadVar locTypes rTy ty r
  ops
  ret ty

unaryOp : InferredType -> (InferredType -> Asm ()) -> Asm () -> LVar -> Asm ()
unaryOp ty ret ops x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy ty x
  ops
  ret ty

compareOp : InferredType -> (InferredType -> Asm ()) -> MethodName -> LVar -> LVar -> Asm ()
compareOp ty ret fn l r = do
  locTypes <- GetFunctionLocTypes
  let lTy = getLocTy locTypes l
  let rTy = getLocTy locTypes r
  loadVar locTypes lTy ty l
  loadVar locTypes rTy ty r
  let tyDesc = inferredTypeToFieldTypeDesc ty
  let fnDesc = asmMethodDesc $ MkMethodDescriptor [tyDesc, tyDesc] (FieldDescriptor FieldTyDescBoolean)
  InvokeMethod InvokeStatic utilClass fn fnDesc False
  ret IBool

cgExternalOp : (InferredType -> Asm ()) -> String -> List LVar -> Asm ()
cgExternalOp ret op _ =
  if op == "prim__null"
    then do Aconstnull; ret IUnknown
    else do invokeError $ "OPERATOR " ++ show op ++ " NOT IMPLEMENTED!"; ret IUnknown

lcrash : (InferredType -> Asm ()) -> LVar -> Asm ()
lcrash ret x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredStringType x
  InvokeMethod InvokeStatic (rtClass "Runtime") "crash" "(Ljava/lang/String;)Ljava/lang/Object;" False
  ret IUnknown

lsystemInfo : (InferredType -> Asm ()) -> LVar -> Asm ()
lsystemInfo ret x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IInt x
  InvokeMethod InvokeStatic (rtClass "Runtime") "systemInfo" "(I)Ljava/lang/String;" False
  ret inferredStringType

cgOpStrToInt : (InferredType -> Asm ()) -> LVar -> Asm ()
cgOpStrToInt ret x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredStringType x
  InvokeMethod InvokeStatic "java/lang/Integer" "parseInt" "(Ljava/lang/String;)I" False
  ret IInt

cgOpStrToDouble : (InferredType -> Asm ()) -> LVar -> Asm ()
cgOpStrToDouble ret x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredStringType x
  InvokeMethod InvokeStatic "java/lang/Double" "parseDouble" "(Ljava/lang/String;)D" False
  ret IDouble

bigIntegerToChar : (InferredType -> Asm ()) -> LVar -> Asm ()
bigIntegerToChar ret x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredBigIntegerType x
  InvokeMethod InvokeVirtual "java/math/BigInteger" "intValue" "()I" False
  I2c
  ret IChar

intToBigInteger : (InferredType -> Asm ()) -> LVar -> Asm ()
intToBigInteger ret x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IInt x
  I2l
  InvokeMethod InvokeStatic "java/math/BigInteger" "valueOf"  "(J)Ljava/math/BigInteger;" False
  ret inferredBigIntegerType

bits8ToBigInteger : (InferredType -> Asm ()) -> LVar -> Asm ()
bits8ToBigInteger ret x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IInt x
  InvokeMethod InvokeStatic "java/lang/Byte" "toUnsignedLong"  "(B)J" False
  InvokeMethod InvokeStatic "java/math/BigInteger" "valueOf"  "(J)Ljava/math/BigInteger;" False
  ret inferredBigIntegerType

bits64ToBigInteger : (InferredType -> Asm ()) -> LVar -> Asm ()
bits64ToBigInteger ret x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy ILong x
  InvokeMethod InvokeStatic "java/lang/Long" "toUnsignedString"  "(J)Ljava/lang/String;" False
  InvokeMethod InvokeSpecial "java/math/BigInteger" "<init>"  "(Ljava/lang/String;)V" False
  ret inferredBigIntegerType

bigIntegerToInt : (InferredType -> Asm ()) -> LVar -> Asm ()
bigIntegerToInt ret x = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredBigIntegerType x
  InvokeMethod InvokeVirtual "java/math/BigInteger" "intValue" "()I" False
  ret IInt

longToChar : (InferredType -> Asm ()) -> LVar -> Asm ()
longToChar ret x = do
   locTypes <- GetFunctionLocTypes
   let xTy = getLocTy locTypes x
   loadVar locTypes xTy ILong x
   L2i
   I2c
   ret IChar

longToInt : (InferredType -> Asm ()) -> LVar -> Asm ()
longToInt ret x = do
   locTypes <- GetFunctionLocTypes
   let xTy = getLocTy locTypes x
   loadVar locTypes xTy ILong x
   L2i
   ret IInt

longToBigInteger : (InferredType -> Asm ()) -> LVar -> Asm ()
longToBigInteger ret x = do
   locTypes <- GetFunctionLocTypes
   let xTy = getLocTy locTypes x
   loadVar locTypes xTy ILong x
   InvokeMethod InvokeStatic "java/math/BigInteger" "valueOf"  "(J)Ljava/math/BigInteger;" False
   ret inferredBigIntegerType

intToInt : (InferredType -> Asm ()) -> LVar -> Asm ()
intToInt ret var = do
  locTypes <- GetFunctionLocTypes
  let varTy = getLocTy locTypes var
  loadVar locTypes varTy IInt var
  ret IInt

intToChar : (InferredType -> Asm ()) -> LVar -> Asm ()
intToChar ret x = do
    locTypes <- GetFunctionLocTypes
    let xTy = getLocTy locTypes x
    loadVar locTypes xTy IInt x
    I2c
    ret IChar

intToLong : (InferredType -> Asm ()) -> LVar -> Asm ()
intToLong ret var = do
  locTypes <- GetFunctionLocTypes
  let varTy = getLocTy locTypes var
  loadVar locTypes varTy IInt var
  I2l
  ret ILong

cgOpLLe : (InferredType -> Asm ()) -> IntTy -> List LVar -> Asm ()
cgOpLLe ret ITBig [l, r] = compareOp inferredBigIntegerType ret "bigIntegerLessThanOrEqualTo" l r
cgOpLLe ret ITNative [l, r] = compareOp IInt ret "uintLessThanOrEqualTo" l r
cgOpLLe ret (ITFixed IT8) [l, r] =  compareOp IInt ret "uintLessThanOrEqualTo" l r
cgOpLLe ret (ITFixed IT16) [l, r] = compareOp IInt ret "uintLessThanOrEqualTo" l r
cgOpLLe ret (ITFixed IT32) [l, r] = compareOp IInt ret "uintLessThanOrEqualTo" l r
cgOpLLe ret (ITFixed IT64) [l, r] = compareOp ILong ret "ulongLessThanOrEqualTo" l r

cgOpLLt : (InferredType -> Asm ()) -> IntTy -> List LVar -> Asm ()
cgOpLLt ret ITBig [l, r] = compareOp inferredBigIntegerType ret "bigIntegerLessThan" l r
cgOpLLt ret ITNative [l, r] = compareOp IInt ret "uintLessThan" l r
cgOpLLt ret (ITFixed IT8) [l, r] = compareOp IInt ret "uintLessThan" l r
cgOpLLt ret (ITFixed IT16) [l, r] = compareOp IInt ret "uintLessThan" l r
cgOpLLt ret (ITFixed IT32) [l, r] = compareOp IInt ret "uintLessThan" l r
cgOpLLt ret (ITFixed IT64) [l, r] = compareOp ILong ret "ulongLessThan" l r

cgOpLGt : (InferredType -> Asm ()) -> IntTy -> List LVar -> Asm ()
cgOpLGt ret ITBig [l, r] = compareOp inferredBigIntegerType ret "bigIntegerGreaterThan" l r
cgOpLGt ret ITNative [l, r] = compareOp IInt ret "uintGreaterThan" l r
cgOpLGt ret (ITFixed IT8) [l, r] = compareOp IInt ret "uintGreaterThan" l r
cgOpLGt ret (ITFixed IT16) [l, r] = compareOp IInt ret "uintGreaterThan" l r
cgOpLGt ret (ITFixed IT32) [l, r] = compareOp IInt ret "uintGreaterThan" l r
cgOpLGt ret (ITFixed IT64) [l, r] = compareOp ILong ret "ulongGreaterThan" l r

cgOpLGe : (InferredType -> Asm ()) -> IntTy -> List LVar -> Asm ()
cgOpLGe ret ITBig [l, r] = compareOp inferredBigIntegerType ret "bigIntegerGreaterThanOrEqualTo" l r
cgOpLGe ret ITNative [l, r] = compareOp IInt ret "uintGreaterThanOrEqualTo" l r
cgOpLGe ret (ITFixed IT8) [l, r] = compareOp IInt ret "uintGreaterThanOrEqualTo" l r
cgOpLGe ret (ITFixed IT16) [l, r] = compareOp IInt ret "uintGreaterThanOrEqualTo" l r
cgOpLGe ret (ITFixed IT32) [l, r] = compareOp IInt ret "uintGreaterThanOrEqualTo" l r
cgOpLGe ret (ITFixed IT64) [l, r] = compareOp ILong ret "ulongGreaterThanOrTo" l r

cgOpLPlus : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLPlus ret ATFloat [l, r] = binaryOp IDouble ret Dadd l r
cgOpLPlus ret (ATInt ITBig) [lvar, rvar] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "add"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op lvar rvar
cgOpLPlus ret (ATInt ITNative) [l, r] = binaryOp IInt ret Iadd l r
cgOpLPlus ret (ATInt ITChar) [lvar, rvar] =
  let ops = do Iadd; I2c
  in binaryOp IChar ret ops lvar rvar
cgOpLPlus ret (ATInt (ITFixed IT64)) [l, r] = binaryOp ILong ret Ladd l r
cgOpLPlus ret (ATInt (ITFixed IT8)) [l, r] =
  let ops = do Iadd; Iconst 256; Irem
  in binaryOp IInt ret ops l r
cgOpLPlus ret (ATInt (ITFixed _)) [l, r] = binaryOp IInt ret Iadd l r

cgOpLMinus : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLMinus ret ATFloat [l, r] = binaryOp IDouble ret Dsub l r
cgOpLMinus ret (ATInt ITBig) [lvar, rvar] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "subtract"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op lvar rvar
cgOpLMinus ret (ATInt ITNative) [l, r] = binaryOp IInt ret Isub l r
cgOpLMinus ret (ATInt (ITFixed IT64)) [l, r] = binaryOp ILong ret Lsub l r
cgOpLMinus ret (ATInt (ITFixed _)) [l, r] = binaryOp IInt ret Isub l r

cgOpLTimes : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLTimes ret ATFloat [l, r] = binaryOp IDouble ret Dmul l r
cgOpLTimes ret (ATInt ITBig) [lvar, rvar] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "multiply"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op lvar rvar
cgOpLTimes ret (ATInt ITNative) [l, r] = binaryOp IInt ret Imul l r
cgOpLTimes ret (ATInt (ITFixed IT64)) [l, r] = binaryOp ILong ret Lmul l r
cgOpLTimes ret (ATInt (ITFixed IT8)) [l, r] = binaryOp IInt ret ops l r where
  ops = do Imul; Iconst 256; Irem
cgOpLTimes ret (ATInt (ITFixed _)) [l, r] = binaryOp IInt ret Imul l r

cgOpLSDiv : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLSDiv ret ATFloat [l, r] = binaryOp IDouble ret Ddiv l r
cgOpLSDiv ret (ATInt ITBig) [lvar, rvar] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "divide"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op lvar rvar
cgOpLSDiv ret (ATInt ITNative) [l, r] = binaryOp IInt ret Idiv l r
cgOpLSDiv ret (ATInt (ITFixed IT64)) [l, r] = binaryOp ILong ret Ldiv l r
cgOpLSDiv ret (ATInt (ITFixed _)) [l, r] = binaryOp IInt ret Idiv l r

cgOpLUDiv : (InferredType -> Asm ()) -> IntTy -> List LVar -> Asm ()
cgOpLUDiv ret ITNative [l, r] = binaryOp IInt ret udiv l r where
  udiv = InvokeMethod InvokeStatic "java/lang/Integer" "divideUnsigned" "(II)I" False
cgOpLUDiv ret (ITFixed IT32) [l, r] = binaryOp IInt ret udiv l r where
  udiv = InvokeMethod InvokeStatic "java/lang/Integer" "divideUnsigned" "(II)I" False
cgOpLUDiv ret (ITFixed IT64) [l, r] = binaryOp ILong ret udiv l r where
  udiv = InvokeMethod InvokeStatic "java/lang/Long" "divideUnsigned" "(JJ)J" False
cgOpLUDiv ret (ITFixed IT16) [l, r] = binaryOp IInt ret udiv l r where
  udiv = InvokeMethod InvokeStatic (rtClass "Bits16s") "divideUnsigned" "(II)I" False
cgOpLUDiv ret (ITFixed IT8) [l, r] = binaryOp IInt ret udiv l r where
  udiv = InvokeMethod InvokeStatic (rtClass "Bits8s") "divideUnsigned" "(II)I" False
cgOpLUDiv ret ITBig [lvar, rvar] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "divide"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op lvar rvar

cgOpLSRem : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLSRem ret ATFloat [l, r] = binaryOp IDouble ret Drem l r
cgOpLSRem ret (ATInt ITBig) [lvar, rvar] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "remainder"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op lvar rvar
cgOpLSRem ret (ATInt ITNative) [l, r] = binaryOp IInt ret Irem l r
cgOpLSRem ret (ATInt (ITFixed IT64)) [l, r] = binaryOp ILong ret Lrem l r
cgOpLSRem ret (ATInt (ITFixed _)) [l, r] = binaryOp IInt ret Irem l r

cgOpLURem : (InferredType -> Asm ()) -> IntTy -> List LVar -> Asm ()
cgOpLURem ret (ITFixed IT64) [l, r] = binaryOp ILong ret urem l r where
  urem = InvokeMethod InvokeStatic "java/lang/Long" "remainderUnsigned" "(JJ)J" False
cgOpLURem ret ITNative [l, r] = binaryOp IInt ret urem l r where
  urem = InvokeMethod InvokeStatic "java/lang/Integer" "remainderUnsigned" "(II)I" False
cgOpLURem ret (ITFixed IT32) [l, r] = binaryOp IInt ret urem l r where
  urem = InvokeMethod InvokeStatic "java/lang/Integer" "remainderUnsigned" "(II)I" False
cgOpLURem ret ITBig [lvar, rvar] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "mod"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op lvar rvar
cgOpLURem ret (ITFixed _) [l, r] = binaryOp IInt ret Irem l r

cgOpLEq : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLEq ret ATFloat [l, r] = compareOp IDouble ret "doubleEquals" l r
cgOpLEq ret (ATInt ITBig) [l, r] = compareOp inferredBigIntegerType ret "bigIntegerEquals" l r
cgOpLEq ret (ATInt (ITFixed IT64)) [l, r] = compareOp ILong ret "longEquals" l r
cgOpLEq ret (ATInt ITChar) [l, r] = compareOp IChar ret "charEquals" l r
cgOpLEq ret (ATInt _) [l, r] = compareOp IInt ret "intEquals" l r

cgOpLSLt : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLSLt ret ATFloat [l, r] = compareOp IDouble ret "doubleLessThan" l r
cgOpLSLt ret (ATInt ITNative) [l, r] = compareOp IInt ret "intLessThan" l r
cgOpLSLt ret (ATInt ITBig) [l, r] = compareOp inferredBigIntegerType ret "bigIntegerLessThan" l r
cgOpLSLt ret (ATInt ITChar) [l, r] = compareOp IChar ret "charLessThan" l r
cgOpLSLt ret (ATInt (ITFixed IT64)) [l, r] = compareOp ILong ret "longLessThan" l r
cgOpLSLt ret (ATInt (ITFixed _)) [l, r] = compareOp IInt ret "intLessThan" l r

cgOpLSLe : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLSLe ret ATFloat [l, r] = compareOp IDouble ret "doubleLessThanOrEqualTo" l r
cgOpLSLe ret (ATInt ITNative) [l, r] = compareOp IInt ret "intLessThanOrEqualTo" l r
cgOpLSLe ret (ATInt ITBig) [l, r] = compareOp inferredBigIntegerType ret "bigIntegerLessThanOrEqualTo" l r
cgOpLSLe ret (ATInt ITChar) [l, r] = compareOp IChar ret "charLessThanOrEqualTo" l r
cgOpLSLe ret (ATInt (ITFixed IT64)) [l, r] = compareOp ILong ret "longLessThanOrEqualTo" l r
cgOpLSLe ret (ATInt (ITFixed _)) [l, r] = compareOp IInt ret "intLessThanOrEqualTo" l r

cgOpLSGt : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLSGt ret ATFloat [l, r] = compareOp IDouble ret "doubleGreaterThan" l r
cgOpLSGt ret (ATInt ITNative) [l, r] = compareOp IInt ret "intGreaterThan" l r
cgOpLSGt ret (ATInt ITBig) [l, r] = compareOp inferredBigIntegerType ret "bigIntegerGreaterThan" l r
cgOpLSGt ret (ATInt ITChar) [l, r] = compareOp IChar ret "charGreaterThan" l r
cgOpLSGt ret (ATInt (ITFixed IT64)) [l, r] = compareOp ILong ret "longGreaterThan" l r
cgOpLSGt ret (ATInt (ITFixed _)) [l, r] = compareOp IInt ret "intGreaterThan" l r

cgOpLSGe : (InferredType -> Asm ()) -> ArithTy -> List LVar -> Asm ()
cgOpLSGe ret ATFloat [l, r] = compareOp IDouble ret "doubleGreaterThanOrEqualTo" l r
cgOpLSGe ret (ATInt ITNative) [l, r] = compareOp IInt ret "intGreaterThanOrEqualTo" l r
cgOpLSGe ret (ATInt ITBig) [l, r] = compareOp inferredBigIntegerType ret "bigIntegerGreaterThanOrEqualTo" l r
cgOpLSGe ret (ATInt ITChar) [l, r] = compareOp IChar ret "charGreaterThanOrEqualTo" l r
cgOpLSGe ret (ATInt (ITFixed IT64)) [l, r] = compareOp ILong ret "longGreaterThanOrEqualTo" l r
cgOpLSGe ret (ATInt (ITFixed _)) [l, r] = compareOp IInt ret "intGreaterThanOrEqualTo" l r

cgOpLZExt : (InferredType -> Asm ()) -> IntTy -> IntTy -> List LVar -> Asm ()
cgOpLZExt ret ITNative ITBig [var] = intToBigInteger ret var
cgOpLZExt ret (ITFixed IT64) ITBig [var] = bits64ToBigInteger ret var
cgOpLZExt ret (ITFixed IT8) ITBig [var] = bits8ToBigInteger ret var
cgOpLZExt ret (ITFixed from) ITBig [var] = intToBigInteger ret var

cgOpLZExt ret (ITFixed from) (ITFixed IT64) [var] = intToLong ret var
cgOpLZExt ret ITNative (ITFixed IT64) [var] = intToLong ret var
cgOpLZExt ret ITChar (ITFixed IT64) [var] = intToLong ret var

cgOpLZExt ret ITNative (ITFixed to) [var] = intToInt ret var
cgOpLZExt ret (ITFixed IT64) ITNative [var] = longToInt ret var
cgOpLZExt ret (ITFixed from) ITNative [var] = intToInt ret var
cgOpLZExt ret ITChar ITNative [var] = intToInt ret var
cgOpLZExt ret ITChar (ITFixed to) [var] = intToInt ret var

cgOpLZExt ret (ITFixed IT64) ITChar [var] = longToChar ret var
cgOpLZExt ret (ITFixed from) ITChar [var] = intToChar ret var

cgOpLStrRev : (InferredType -> Asm ()) -> LVar -> Asm ()
cgOpLStrRev ret var = do
  New "java/lang/StringBuilder"
  Dup
  locTypes <- GetFunctionLocTypes
  let varTy = getLocTy locTypes var
  loadVar locTypes varTy inferredStringType var
  InvokeMethod InvokeSpecial "java/lang/StringBuilder" "<init>" "(Ljava/lang/String;)V" False
  InvokeMethod InvokeVirtual "java/lang/StringBuilder" "reverse" "()Ljava/lang/StringBuilder;" False
  InvokeMethod InvokeVirtual "java/lang/StringBuilder" "toString" "()Ljava/lang/String;" False
  ret inferredStringType

cgOpLStrLen : (InferredType -> Asm ()) -> LVar -> Asm ()
cgOpLStrLen ret var = do
  locTypes <- GetFunctionLocTypes
  let varTy = getLocTy locTypes var
  loadVar locTypes varTy inferredStringType var
  InvokeMethod InvokeVirtual "java/lang/String" "length" "()I" False
  ret IInt

cgOpLStrHead : (InferredType -> Asm ()) -> LVar -> Asm ()
cgOpLStrHead ret var = do
  locTypes <- GetFunctionLocTypes
  let varTy = getLocTy locTypes var
  loadVar locTypes varTy inferredStringType var
  InvokeMethod InvokeStatic (rtClass "Strings") "strHead" "(Ljava/lang/String;)C" False
  ret IChar

cgOpLStrIndex : (InferredType -> Asm ()) -> LVar -> LVar -> Asm ()
cgOpLStrIndex ret string index = do
  locTypes <- GetFunctionLocTypes
  let stringTy = getLocTy locTypes string
  loadVar locTypes stringTy inferredStringType string
  let indexTy = getLocTy locTypes index
  loadVar locTypes indexTy IInt index
  InvokeMethod InvokeStatic (rtClass "Strings") "strIndex" "(Ljava/lang/String;I)C" False
  ret IChar

cgOpLStrTail : (InferredType -> Asm ()) -> LVar -> Asm ()
cgOpLStrTail ret var = do
  locTypes <- GetFunctionLocTypes
  let varTy = getLocTy locTypes var
  loadVar locTypes varTy inferredStringType var
  Iconst 1
  InvokeMethod InvokeVirtual "java/lang/String" "substring" "(I)Ljava/lang/String;" False
  ret inferredStringType

cgOpLStrConcat : (InferredType -> Asm ()) -> LVar -> LVar -> Asm ()
cgOpLStrConcat ret l r = do
  New "java/lang/StringBuilder"
  Dup
  InvokeMethod InvokeSpecial "java/lang/StringBuilder" "<init>" "()V" False
  locTypes <- GetFunctionLocTypes
  let lTy = getLocTy locTypes l
  loadVar locTypes lTy inferredStringType l
  InvokeMethod InvokeVirtual "java/lang/StringBuilder" "append" "(Ljava/lang/String;)Ljava/lang/StringBuilder;" False
  let rTy = getLocTy locTypes r
  loadVar locTypes rTy inferredStringType r
  InvokeMethod InvokeVirtual "java/lang/StringBuilder" "append" "(Ljava/lang/String;)Ljava/lang/StringBuilder;" False
  InvokeMethod InvokeVirtual "java/lang/StringBuilder" "toString" "()Ljava/lang/String;" False
  ret inferredStringType

cgOpLStrCons : (InferredType -> Asm ()) -> LVar -> LVar -> Asm ()
cgOpLStrCons ret l r = do
  New "java/lang/StringBuilder"
  Dup
  InvokeMethod InvokeSpecial "java/lang/StringBuilder" "<init>" "()V" False
  locTypes <- GetFunctionLocTypes
  let lTy = getLocTy locTypes l
  loadVar locTypes lTy IChar l
  InvokeMethod InvokeVirtual "java/lang/StringBuilder" "append" "(C)Ljava/lang/StringBuilder;" False
  let rTy = getLocTy locTypes r
  loadVar locTypes rTy inferredStringType r
  InvokeMethod InvokeVirtual "java/lang/StringBuilder" "append" "(Ljava/lang/String;)Ljava/lang/StringBuilder;" False
  InvokeMethod InvokeVirtual "java/lang/StringBuilder" "toString" "()Ljava/lang/String;" False
  ret inferredStringType

cgOpLStrSubstr : (InferredType -> Asm ()) -> LVar -> LVar -> LVar -> Asm ()
cgOpLStrSubstr ret offset len str = do
  locTypes <- GetFunctionLocTypes
  let strTy = getLocTy locTypes str
  loadVar locTypes strTy inferredStringType str
  let offsetTy = getLocTy locTypes offset
  loadVar locTypes offsetTy IInt offset
  let lenTy = getLocTy locTypes len
  loadVar locTypes lenTy IInt len
  InvokeMethod InvokeStatic (rtClass "Runtime") "substring" "(Ljava/lang/String;II)Ljava/lang/String;" False
  ret inferredStringType

cgOpBigIntegerUnaryIntOp : (InferredType -> Asm ()) -> Asm () -> LVar -> LVar -> Asm ()
cgOpBigIntegerUnaryIntOp ret op x y = do
  locTypes <- GetFunctionLocTypes
  let lTy = getLocTy locTypes x
  let rTy = getLocTy locTypes y
  loadVar locTypes lTy inferredBigIntegerType x
  loadVar locTypes rTy IInt y
  op
  ret inferredBigIntegerType

cgOpNotImplemented : PrimFn -> Asm ()
cgOpNotImplemented op = invokeError $ "OPERATOR " ++ show op ++ " NOT IMPLEMENTED!"

-- cgOp split into two to avoid JVM's "Method code too large" error.
cgOp2 : (InferredType -> Asm ()) -> PrimFn -> List LVar -> Asm ()
cgOp2 ret (LIntStr ITBig) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredBigIntegerType x
  InvokeMethod InvokeVirtual "java/math/BigInteger" "toString" "()Ljava/lang/String;" False
  ret inferredStringType

cgOp2 ret (LIntStr (ITFixed IT64)) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy ILong x
  InvokeMethod InvokeStatic "java/lang/Long" "toUnsignedString" "(J)Ljava/lang/String;" False
  ret inferredStringType

cgOp2 ret (LIntStr _) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IInt x
  InvokeMethod InvokeStatic "java/lang/Integer" "toString" "(I)Ljava/lang/String;" False
  ret inferredStringType

cgOp2 ret LFloatStr [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IDouble x
  InvokeMethod InvokeStatic (rtClass "Doubles") "toString" "(D)Ljava/lang/String;" False
  ret inferredStringType

cgOp2 ret (LChInt ITBig) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IChar x
  I2l
  InvokeMethod InvokeStatic "java/math/BigInteger" "valueOf"  "(J)Ljava/math/BigInteger;" False
  ret inferredBigIntegerType

cgOp2 ret (LChInt (ITFixed IT64)) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IChar x
  I2l
  ret ILong

cgOp2 ret (LChInt _) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IChar x
  ret IInt

cgOp2 ret (LIntCh ITBig) [x] = bigIntegerToChar ret x

cgOp2 ret (LIntCh (ITFixed IT64)) [x] = longToChar ret x

cgOp2 ret (LIntCh _) [x] = intToChar ret x

cgOp2 ret (LSExt ITNative ITBig) [x] = intToBigInteger ret x

cgOp2 ret (LSExt (ITFixed IT64) ITBig) [x] = longToBigInteger ret x

cgOp2 ret (LSExt (ITFixed _) ITBig) [x] = intToBigInteger ret x

cgOp2 ret (LTrunc ITNative (ITFixed IT64)) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IInt x
  I2l
  ret ILong

cgOp2 ret (LTrunc (ITFixed IT64) (ITFixed _)) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy ILong x
  L2i
  ret IInt

cgOp2 ret (LTrunc ITBig (ITFixed IT64)) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredBigIntegerType x
  InvokeMethod InvokeVirtual "java/math/BigInteger" "longValue" "()J" False
  ret ILong

cgOp2 ret (LTrunc ITBig (ITFixed _)) [x] = bigIntegerToInt ret x

cgOp2 ret (LTrunc ITBig ITNative) [x] = bigIntegerToInt ret x

cgOp2 ret (LTrunc (ITFixed _) (ITFixed _)) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IInt x
  ret IInt

cgOp2 ret LWriteStr [_, x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredStringType x
  InvokeMethod InvokeStatic (rtClass "Runtime") "writeString" "(Ljava/lang/String;)I" False
  ret IInt

cgOp2 ret LReadStr [_] = do
  InvokeMethod InvokeStatic (rtClass "Runtime") "readString" "()Ljava/lang/String;" False
  ret inferredStringType

cgOp2 ret LStrConcat [l,r] = cgOpLStrConcat ret l r

cgOp2 ret LStrCons [l,r] = cgOpLStrCons ret l r

cgOp2 ret LStrSubstr [offset, len, str] = cgOpLStrSubstr ret offset len str

cgOp2 ret (LStrInt ITBig) [x] = do
  New "java/math/BigInteger"
  Dup
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredStringType x
  InvokeMethod InvokeSpecial "java/math/BigInteger" "<init>" "(Ljava/lang/String;)V" False
  ret inferredBigIntegerType

cgOp2 ret (LStrInt (ITFixed IT8)) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredStringType x
  Iconst 16
  InvokeMethod InvokeStatic "java/lang/Integer" "parseInt" "(Ljava/lang/String;I)I" False
  ret IInt

cgOp2 ret (LStrInt _) [x] = cgOpStrToInt ret x

cgOp2 ret LStrFloat [x] = cgOpStrToDouble ret x

cgOp2 ret (LSHL (ITFixed IT64)) [x, y] = binaryOp ILong ret ops x y where
  ops = do L2i; Lshl

cgOp2 ret (LSHL (ITFixed IT8)) [x, y] = binaryOp IInt ret ops x y where
  ops = do Ishl; Iconst 256; Irem

cgOp2 ret (LSHL (ITFixed _)) [x, y] = binaryOp IInt ret Ishl x y

cgOp2 ret (LSHL ITBig) [x, y] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "shiftLeft" "(I)Ljava/math/BigInteger;" False
  in cgOpBigIntegerUnaryIntOp ret op x y

cgOp2 ret (LLSHR (ITFixed IT64)) [x, y] = binaryOp ILong ret ops x y where
  ops = do L2i; Lushr

cgOp2 ret (LLSHR (ITFixed _)) [x, y] = binaryOp IInt ret Iushr x y

cgOp2 ret (LLSHR ITBig) [x, y] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "shiftRight" "(I)Ljava/math/BigInteger;" False
  in cgOpBigIntegerUnaryIntOp ret op x y

cgOp2 ret (LASHR (ITFixed IT64)) [x, y] = binaryOp ILong ret ops x y where
  ops = do L2i; Lshr

cgOp2 ret (LASHR (ITFixed _)) [x, y] = binaryOp IInt ret Ishr x y

cgOp2 ret (LASHR ITBig) [x, y] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "shiftRight" "(I)Ljava/math/BigInteger;" False
  in cgOpBigIntegerUnaryIntOp ret op x y

cgOp2 ret LFork [x] = do
  caller <- GetFunctionName
  createThunk caller (jname "{EVAL_0}") [x]
  InvokeMethod InvokeStatic (rtClass "Concurrent") "fork" ("(" ++ rtThunkSig ++ ")" ++ classSig futureClass) False
  ret (Ref futureClass)

cgOp2 ret LPar [x] = do
  caller <- GetFunctionName
  createParThunk caller (jname "{EVAL_0}") [x]
  InvokeMethod InvokeStatic (rtClass "Concurrent") "par" ("(" ++ rtThunkSig ++ ")" ++ classSig objectClass) False
  ret (Ref objectClass)

cgOp2 ret (LIntFloat ITBig) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy inferredBigIntegerType x
  InvokeMethod InvokeVirtual "java/math/BigInteger" "doubleValue" "()D" False
  ret IDouble

cgOp2 ret (LIntFloat ITNative) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IInt x
  I2d
  ret IDouble

cgOp2 ret (LFloatInt ITBig) [x] = do
  New "java/math/BigDecimal"
  Dup
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IDouble x
  InvokeMethod InvokeSpecial "java/math/BigDecimal" "<init>" "(D)V" False
  InvokeMethod InvokeVirtual "java/math/BigDecimal" "toBigInteger" "()Ljava/math/BigInteger;" False
  ret inferredBigIntegerType

cgOp2 ret (LFloatInt ITNative) [x] = do
  locTypes <- GetFunctionLocTypes
  let xTy = getLocTy locTypes x
  loadVar locTypes xTy IDouble x
  D2i
  ret IInt

cgOp2 ret LSystemInfo [x] = lsystemInfo ret x

cgOp2 ret LCrash [x] = lcrash ret x

cgOp2 ret (LExternal externalOp) args = cgExternalOp ret externalOp args

cgOp2 ret op _ = do cgOpNotImplemented op; ret IUnknown

cgOp : (InferredType -> Asm ()) -> PrimFn -> List LVar -> Asm ()
cgOp ret (LAnd (ITFixed IT64)) [l, r] = binaryOp ILong ret Land l r
cgOp ret (LAnd (ITFixed _)) [l, r] = binaryOp IInt ret Iand l r
cgOp ret (LAnd ITNative) [l, r] = binaryOp IInt ret Iand l r
cgOp ret (LAnd ITBig) [l, r] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "and"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op l r

cgOp ret (LOr (ITFixed IT64)) [l, r] = binaryOp ILong ret Lor l r
cgOp ret (LOr (ITFixed _)) [l, r] = binaryOp IInt ret Ior l r
cgOp ret (LOr ITNative) [l, r] = binaryOp IInt ret Ior l r
cgOp ret (LOr ITBig) [l, r] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "or"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op l r

cgOp ret (LXOr (ITFixed IT64)) [l, r] = binaryOp ILong ret Lxor l r
cgOp ret (LXOr (ITFixed _)) [l, r] = binaryOp IInt ret Ixor l r
cgOp ret (LXOr ITNative) [l, r] = binaryOp IInt ret Ixor l r
cgOp ret (LXOr ITBig) [l, r] =
  let op = InvokeMethod InvokeVirtual "java/math/BigInteger" "xor"  "(Ljava/math/BigInteger;)Ljava/math/BigInteger;" False
  in binaryOp inferredBigIntegerType ret op l r

cgOp ret (LCompl (ITFixed IT64)) [x] = unaryOp ILong ret Lcompl x
cgOp ret (LCompl (ITFixed _)) [x] = unaryOp IInt ret Icompl x
cgOp ret (LCompl ITNative) [x] = unaryOp IInt ret Icompl x

cgOp ret (LLt intTy) args = cgOpLLt ret intTy args

cgOp ret (LLe intTy) args = cgOpLLe ret intTy args

cgOp ret (LGt intTy) args = cgOpLGt ret intTy args

cgOp ret (LGe intTy) args = cgOpLGe ret intTy args

cgOp ret (LPlus arithTy) args = cgOpLPlus ret arithTy args

cgOp ret (LMinus arithTy) args = cgOpLMinus ret arithTy args

cgOp ret (LTimes arithTy) args = cgOpLTimes ret arithTy args

cgOp ret (LSDiv arithTy) args = cgOpLSDiv ret arithTy args

cgOp ret (LUDiv arithTy) args = cgOpLUDiv ret arithTy args

cgOp ret (LSRem arithTy) args = cgOpLSRem ret arithTy args

cgOp ret (LURem intTy) args = cgOpLURem ret intTy args

cgOp ret (LEq arithTy) args = cgOpLEq ret arithTy args

cgOp ret (LSLt arithTy) args = cgOpLSLt ret arithTy args

cgOp ret (LSLe arithTy) args = cgOpLSLe ret arithTy args

cgOp ret (LSGt arithTy) args = cgOpLSGt ret arithTy args

cgOp ret (LSGe arithTy) args = cgOpLSGe ret arithTy args

cgOp ret LStrEq [l,r] = compareOp inferredStringType ret "stringEquals" l r

cgOp ret LStrRev [var] = cgOpLStrRev ret var

cgOp ret LStrLen [var] = cgOpLStrLen ret var

cgOp ret LStrLt [l, r] = compareOp inferredStringType ret "stringLessThan" l r

cgOp ret LStrHead [var] = cgOpLStrHead ret var

cgOp ret LStrIndex [string, index] = cgOpLStrIndex ret string index

cgOp ret LStrTail [var] = cgOpLStrTail ret var

cgOp ret (LZExt from to) args = cgOpLZExt ret from to args

cgOp ret op args = cgOp2 ret op args
