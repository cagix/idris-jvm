module Compiler.Jvm.Export

import Compiler.Common
import Compiler.CompileExpr
import Compiler.Inline
import Compiler.NoMangle
import Compiler.Jvm.Asm
import Compiler.Jvm.InferredType
import Compiler.Jvm.Jname
import Compiler.Jvm.Optimizer
import Compiler.Jvm.Variable
import Core.Context
import Core.Directory
import Core.Name
import Core.Name.Namespace
import Core.Options
import Core.TT
import Data.List
import Data.List1
import Data.Maybe
import Data.String
import Language.JSON
import Libraries.Data.SortedMap
import Libraries.Utils.Path

import System.FFI

record ExportArgument where
  constructor MkExportArgument
  type: InferredType
  annotations: List Annotation

mutual
  parseAnnotationTypeValue : Name -> String -> String -> JSON -> Asm AnnotationValue
  parseAnnotationTypeValue functionName annotationName "int" (JNumber value) = Pure $ AnnInt $ cast value
  parseAnnotationTypeValue functionName annotationName "boolean" (JBoolean value) = Pure $ AnnBoolean value
  parseAnnotationTypeValue functionName annotationName "char" (JString value) =
    Pure $ AnnChar $ assert_total (prim__strHead value)
  parseAnnotationTypeValue functionName annotationName "double" (JNumber value) = Pure $ AnnDouble value
  parseAnnotationTypeValue functionName annotationName "String" (JString value) = Pure $ AnnString value
  parseAnnotationTypeValue functionName annotationName "class" (JString value) = Pure $ AnnClass value
  parseAnnotationTypeValue functionName annotationName "enum" (JObject properties) = do
    let propertiesByName = SortedMap.fromList properties
    let Just (JString type) = lookup "type" properties
      | _ => asmCrash ("Expected 'string' enum type for annotation " ++ show annotationName ++ " in " ++
               show functionName)
    let Just (JString value) = lookup "value" properties
      | _ => asmCrash ("Expected 'string' enum value for annotation " ++ show annotationName ++ " in " ++
               show functionName)
    Pure $ AnnEnum type value
  parseAnnotationTypeValue functionName annotationName "annotation" annotationJson = do
    annotation <- parseAnnotation functionName annotationJson
    Pure $ AnnAnnotation annotation
  parseAnnotationTypeValue functionName annotationName type _ =
    asmCrash ("Unknown type " ++ show type ++ " for annotation " ++ annotationName ++ " in " ++ show functionName)

  parseAnnotationValue : Name -> String -> JSON -> Asm AnnotationValue
  parseAnnotationValue functionName annotationName (JNumber value) = Pure $ AnnInt $ cast value
  parseAnnotationValue functionName annotationName (JString value) = Pure $ AnnString value
  parseAnnotationValue functionName annotationName (JBoolean value) = Pure $ AnnBoolean value
  parseAnnotationValue functionName annotationName (JObject properties) = do
    let propertiesByName = SortedMap.fromList properties
    let Just (JString type) = lookup "type" propertiesByName
      | _ => asmCrash ("Missing 'string' type for annotation " ++ annotationName ++ " in " ++ show functionName)
    let Just value = SortedMap.lookup "value" propertiesByName
      | _ => asmCrash ("Missing 'string' value for annotation " ++ annotationName ++ " in " ++ show functionName)
    parseAnnotationTypeValue functionName annotationName type value
  parseAnnotationValue functionName annotationName (JArray valuesJson) =
    Pure $ AnnArray !(traverse (parseAnnotationValue functionName annotationName) valuesJson)
  parseAnnotationValue functionName annotationName JNull = asmCrash ("Annotation property value cannot be null " ++
    " for annotation " ++ show annotationName ++ " in function " ++ show functionName)

  parseAnnotationProperty : Name -> String -> String -> JSON -> Asm AnnotationProperty
  parseAnnotationProperty functionName annotationName propertyName valueJson = do
    value <- parseAnnotationValue functionName annotationName valueJson
    Pure $ (propertyName, value)

  parseAnnotation : Name -> JSON -> Asm Annotation
  parseAnnotation functionName (JObject [(annotationName, (JObject propertyNameAndValues))]) = do
    properties <- traverse
      (\(propertyName, value) => parseAnnotationProperty functionName annotationName propertyName value)
      propertyNameAndValues
    Pure $ MkAnnotation annotationName properties
  parseAnnotation functionName (JObject [(annotationName, simplifiedValue)]) =
    parseAnnotation functionName (JObject [(annotationName, (JObject [("value", simplifiedValue)]))])
  parseAnnotation functionName _ =
    asmCrash ("Expected a JSON object for parameter annotations in " ++ show functionName)

parseAnnotations : Name -> JSON -> Asm (List Annotation)
parseAnnotations functionName (JArray annotations) = traverse (parseAnnotation functionName) annotations
parseAnnotations functionName _ = asmCrash ("Expected an array for parameter annotations in " ++ show functionName)

parseArgument : Name -> List (String, JSON) -> Asm ExportArgument
parseArgument functionName keyAndValues = do
  let valuesByKey = SortedMap.fromList keyAndValues
  let Just (JString typeStr) = lookup "type" valuesByKey
    | _ => asmCrash $ "Expected 'string' argument type for " ++ show functionName
  let annotationsJson = fromMaybe (JArray []) $ lookup "annotations" valuesByKey
  annotations <- parseAnnotations functionName annotationsJson
  Pure $ MkExportArgument (parse typeStr) annotations

parseArgumentsJson : Name -> JSON -> Asm (List ExportArgument)
parseArgumentsJson functionName (JArray arguments) = go arguments where
  go : List JSON -> Asm (List ExportArgument)
  go [] = Pure []
  go ((JObject keyAndValues) :: rest) = do
    argument <- parseArgument functionName keyAndValues
    restArguments <- go rest
    Pure (argument :: restArguments)
  go _ = asmCrash ("Expected an argument object for foreign export function: " ++ show functionName)
parseArgumentsJson functionName _ =
  asmCrash ("Expected an array of arguments for foreign export function: " ++ show functionName)

loadArguments : Map Int InferredType -> Name -> Int -> List InferredType -> Asm ()
loadArguments typesByIndex functionName arity idrisTypes = go 0 idrisTypes
  where
    go : Int -> List InferredType -> Asm ()
    go n [] =
      if n == arity
        then pure ()
        else asmCrash ("JVM and Idris types do not match in foreign export for " ++ show functionName)
    go varIndex (idrisType :: rest) = do
      Just jvmType <- nullableToMaybe <$> Map.get typesByIndex varIndex
        | Nothing => asmCrash ("Missing JVM type in foreign export for " ++ show functionName)
      loadVar typesByIndex jvmType idrisType varIndex
      go (varIndex + 1) rest

record ClassExport where
  constructor MkClassExport
  name: String
  idrisName: Name
  extends: String
  implements: List String
  modifiers: List Access
  annotations: List Annotation

record MethodExport where
  constructor MkMethodExport
  name: String
  idrisName: Name
  type: InferredFunctionType
  encloser: ClassExport
  modifiers: List Access
  annotations: List Annotation
  parameterAnnotations: List (List Annotation)

record FieldExport where
  constructor MkFieldExport
  name: String
  idrisName: Name
  type: InferredType
  encloser: ClassExport
  modifiers: List Access
  annotations: List Annotation

data ExportDescriptor : Type where
  MkFieldExportDescriptor : FieldExport -> ExportDescriptor
  MkMethodExportDescriptor : MethodExport -> ExportDescriptor
  MkClassExportDescriptor : ClassExport -> ExportDescriptor
  MkImportDescriptor : Name -> SortedMap String String -> ExportDescriptor

parseModifier : String -> Maybe Access
parseModifier "public" = Just Public
parseModifier "private" = Just Private
parseModifier "static" = Just Static
parseModifier "synthetic" = Just Synthetic
parseModifier "final" = Just Final
parseModifier "interface" = Just Interface
parseModifier "abstract" = Just Abstract
parseModifier invalid = Nothing

parseString : String -> JSON -> Asm String
parseString _ (JString value) = Pure value
parseString errorMessage _ = asmCrash errorMessage

parseClassExport : Name -> (nameParts : List String) -> {auto 0 nonEmpty : NonEmpty nameParts} ->
                    SortedMap String JSON -> List Annotation -> Asm ClassExport
parseClassExport name parts descriptor annotations = do
  let isInterface = "interface" `elem` parts
  extends <- if isInterface
              then Pure "java/lang/Object"
              else case lookup "extends" descriptor of
                     Nothing => Pure "java/lang/Object"
                     Just (JString superName) => Pure superName
                     _ => asmCrash ("Invalid 'extends' for " ++ show name)
  let implementsKey = if isInterface then "extends" else "implements"
  implements <- case lookup implementsKey descriptor of
                  Nothing => Pure []
                  Just (JArray implementsJson) =>
                    traverse (parseString ("Expected a string value for '" ++ implementsKey ++ "' for " ++ show name))
                      implementsJson
                  _ => asmCrash ("Invalid '" ++ implementsKey ++ "' for " ++ show name)
  Pure $ MkClassExport (last parts) name extends implements (mapMaybe parseModifier parts) annotations

getReferenceTypeName : String -> InferredType -> Asm String
getReferenceTypeName _ (IRef name _) = Pure name
getReferenceTypeName functionName _ = asmCrash ("Expected a reference type to export function " ++ functionName)

makePublicByDefault : List Access -> List Access
makePublicByDefault modifiers =
  let accessModifiers = the (List Access) [Public, Private, Protected]
  in if any (flip elem accessModifiers) modifiers
      then modifiers
      else (Public :: modifiers)

parseMethodExport : Name -> (javaName: String) -> (nameParts: List String) -> {auto 0 nonEmpty : NonEmpty nameParts} ->
                      SortedMap String JSON -> List Annotation -> Asm MethodExport
parseMethodExport idrisName javaName parts descriptor annotations = do
    let argumentsJson = fromMaybe (JArray []) $ lookup "arguments" descriptor
    arguments <- parseArgumentsJson idrisName argumentsJson
    let (jvmArgumentTypes, parameterAnnotations) =
          unzip $ (\(MkExportArgument type annotations) => (type, annotations)) <$> arguments
    Just jvmReturnTypeString <-
        traverse (parseString ("Invalid return type for function " ++ javaName)) $ lookup "returnType" descriptor
      | Nothing => asmCrash ("Missing return type for " ++ javaName)
    let jvmReturnType = parse jvmReturnTypeString
    let functionType = MkInferredFunctionType jvmReturnType jvmArgumentTypes
    let modifiers = mapMaybe parseModifier parts
    let adjustedModifiers = makePublicByDefault modifiers
    let isInstance = not $ elem Static modifiers
    let adjustedParameterAnnotations = if isInstance then drop 1 parameterAnnotations else parameterAnnotations
    enclosingTypeName <- if isInstance
      then case jvmArgumentTypes of
        [] => asmCrash ("Expected first argument to be a reference type for instance member in " ++ javaName)
        (enclosingType :: _) => getReferenceTypeName javaName enclosingType
      else case lookup "enclosingType" descriptor of
        Nothing => asmCrash ("Missing 'enclosingType' for " ++ javaName)
        Just enclosingTypeJson => parseString ("Invalid enclosing type for function " ++ javaName) enclosingTypeJson
    encloser <- case words enclosingTypeName of
      [] => asmCrash ("Unable to determine enclosing type for " ++ javaName)
      enclosingTypeParts@(_ :: _) =>
        parseClassExport idrisName enclosingTypeParts SortedMap.empty []
    Pure $ MkMethodExport (last parts) idrisName functionType encloser adjustedModifiers annotations
      adjustedParameterAnnotations

parseFieldExport : Name -> (nameParts: List String) -> {auto 0 nonEmpty : NonEmpty nameParts} ->
                     SortedMap String JSON -> List Annotation -> Asm FieldExport
parseFieldExport name parts descriptor annotations = do
  let modifiers = mapMaybe parseModifier parts
  Just enclosingTypeName <-
      traverse (parseString ("Invalid 'enclosingType' for " ++ show name)) $ lookup "enclosingType" descriptor
    | Nothing => asmCrash ("Missing 'enclosingType' for " ++ show name)
  encloser <- case words enclosingTypeName of
     [] => asmCrash ("Missing enclosing type for " ++ show name)
     enclosingTypeParts@(_ :: _) =>
       parseClassExport name enclosingTypeParts SortedMap.empty []
  Just typeString <-
        traverse (parseString ("Invalid type for field " ++ show name)) $ lookup "type" descriptor
      | Nothing => asmCrash ("Missing type for " ++ show name)
  Pure $ MkFieldExport (last parts) name (parse typeString) encloser modifiers annotations

parseObjectExportDescriptor : Name -> String -> List (String, JSON) -> Asm ExportDescriptor
parseObjectExportDescriptor idrisName javaName descriptorKeyAndValues = do
  let descriptor = SortedMap.fromList descriptorKeyAndValues
  let annotationsJson = fromMaybe (JArray []) $ lookup "annotations" descriptor
  annotations <- parseAnnotations idrisName annotationsJson
  case words javaName of
    [] => asmCrash ("Invalid export descriptor " ++ javaName)
    parts@(_ :: _) =>
      cond
        [
          (isJust $ lookup "returnType" descriptor,
            MkMethodExportDescriptor <$> parseMethodExport idrisName javaName parts descriptor annotations),
          (isJust $ lookup "type" descriptor,
            MkFieldExportDescriptor <$> parseFieldExport idrisName parts descriptor annotations)
        ]
        (MkClassExportDescriptor <$> parseClassExport idrisName parts descriptor annotations)

parseJsonExport : Name -> String -> Asm ExportDescriptor
parseJsonExport functionName descriptor = case String.break (\c => c == '{') descriptor of
  ("", _) => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
  (_, "") => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
  (name, signature) => do
    case JSON.parse signature of
      Just (JObject keyAndValues) => parseObjectExportDescriptor functionName name keyAndValues
      _ => asmCrash ("Invalid foreign export descriptor " ++ descriptor ++ " with signature " ++
             signature ++ " for " ++ show functionName)

parseMethodSimpleExport : Name -> String -> Asm MethodExport
parseMethodSimpleExport functionName descriptor = case String.break (\c => c == '.') descriptor of
  ("", instanceMethodNameAndSig) => case words instanceMethodNameAndSig of
    [] => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (_ :: []) => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (_ :: _ :: []) => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (javaName :: instanceTypeString :: types@(_ :: _)) => do
      let instanceType = parse instanceTypeString
      let functionType = MkInferredFunctionType (parse (last types)) (instanceType :: (parse <$> (init types)))
      className <- getReferenceTypeName ("Invalid instance type in export for " ++ show functionName) instanceType
      let encloser = MkClassExport className functionName "java/lang/Object" [] [Public] []
      Pure $ MkMethodExport javaName functionName functionType encloser [Public] [] []
  (className, staticMethodNameAndArgs) => case words staticMethodNameAndArgs of
    [] => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (_ :: []) => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (javaName :: types@(_ :: _)) => do
      let functionType = MkInferredFunctionType (parse (last types)) (parse <$> (init types))
      let encloser = MkClassExport className functionName "java/lang/Object" [] [Public] []
      Pure $ MkMethodExport javaName functionName functionType encloser [Public, Static] [] []

parseFieldSimpleExport : Name -> String -> Asm FieldExport
parseFieldSimpleExport functionName descriptor = case String.break (\c => c == '#') descriptor of
  ("", instanceFieldNameAndSig) => case words instanceFieldNameAndSig of
    [] => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (_ :: []) => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (_ :: _ :: []) => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (javaName :: instanceType :: type :: _) => do
      className <- getReferenceTypeName ("Invalid instance type in export for " ++ show functionName)
                     (parse instanceType)
      let encloser = MkClassExport className functionName "java/lang/Object" [] [Public] []
      Pure $ MkFieldExport javaName functionName (parse type) encloser [Public] []
  (className, staticFieldNameAndType) => case words staticFieldNameAndType of
    [] => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (_ :: []) => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (javaName :: type :: _) => do
      let encloser = MkClassExport className functionName "java/lang/Object" [] [Public] []
      Pure $ MkFieldExport javaName functionName (parse type) encloser [Public, Static] []

%foreign jvm' "java/lang/Character" "isWhitespace" "char" "boolean"
isWhitespace : Char -> Bool

parseImport : String -> Maybe (String, String)
parseImport line = case words line of
  (type :: []) =>
    let alias = (Prelude.reverse . fst . break (== '/') . Prelude.reverse) type
    in Just (alias, type)
  (type :: alias :: []) => Just (alias, type)
  _ => Nothing

getNamespace : Name -> Namespace
getNamespace (NS n _) = n
getNamespace n = emptyNS

parseImports : Name -> String -> Asm ExportDescriptor
parseImports functionName descriptor =
  case String.break isWhitespace descriptor of
    ("", _) => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (_, "") => asmCrash ("Invalid foreign export descriptor for " ++ show functionName)
    (_, importsDescriptor) =>
      Pure $ MkImportDescriptor functionName $ SortedMap.fromList $ catMaybes $ parseImport <$> lines importsDescriptor

parseExportDescriptor : Name -> String -> Asm ExportDescriptor
parseExportDescriptor functionName descriptor = cond
  [
    ("{" `isInfixOf` descriptor, parseJsonExport functionName descriptor),
    ("." `isInfixOf` descriptor, MkMethodExportDescriptor <$> parseMethodSimpleExport functionName descriptor),
    ("#" `isInfixOf` descriptor, MkFieldExportDescriptor <$> parseFieldSimpleExport functionName descriptor)
  ]
  (parseImports functionName descriptor)

adjustArgumentsForInstanceMember : Name -> (isInstance: Bool) -> List InferredType -> Asm (List InferredType)
adjustArgumentsForInstanceMember _ False argumentTypes = Pure argumentTypes
adjustArgumentsForInstanceMember _ _ (_ :: jvmArgumentTypes) = Pure jvmArgumentTypes
adjustArgumentsForInstanceMember idrisName _ _ =
  asmCrash ("Expected first argument to be a reference type for instance member in " ++ show idrisName)

exportFunction : MethodExport -> Asm ()
exportFunction (MkMethodExport jvmFunctionName idrisName type encloser modifiers annotations parameterAnnotations) = do
    let jvmClassName = encloser.name
    let fileName = fst $ getSourceLocationFromFc emptyFC
    let MkInferredFunctionType jvmReturnType jvmArgumentTypes = type
    let arity = length jvmArgumentTypes
    let arityInt = the Int $ cast $ length jvmArgumentTypes
    jvmArgumentTypesByIndex <- LiftIo $ Map.fromList $ zip [0 .. (arityInt - 1)] jvmArgumentTypes
    let isInstance = not $ elem Static modifiers
    jvmArgumentTypesForSignature <- adjustArgumentsForInstanceMember idrisName isInstance jvmArgumentTypes
    let functionType = getMethodDescriptor (MkInferredFunctionType jvmReturnType jvmArgumentTypesForSignature)
    CreateMethod modifiers fileName jvmClassName jvmFunctionName functionType Nothing Nothing annotations
      parameterAnnotations
    MethodCodeStart
    let jvmIdrisName = jvmName idrisName
    let idrisArgumentTypes = replicate arity inferredObjectType
    let idrisFunctionType = MkInferredFunctionType inferredObjectType idrisArgumentTypes
    loadArguments jvmArgumentTypesByIndex idrisName arityInt (parameterTypes idrisFunctionType)
    let idrisMethodDescriptor = getMethodDescriptor idrisFunctionType
    let qualifiedJvmIdrisName = getIdrisFunctionName !getProgramName (className jvmIdrisName) (methodName jvmIdrisName)
    InvokeMethod InvokeStatic
      (className qualifiedJvmIdrisName) (methodName qualifiedJvmIdrisName) idrisMethodDescriptor False
    when (jvmReturnType == IVoid) $
      InvokeMethod InvokeStatic "main/PrimIO" "unsafePerformIO" "(Ljava/lang/Object;)Ljava/lang/Object;" False
    asmCast (returnType idrisFunctionType) jvmReturnType
    asmReturn jvmReturnType
    MaxStackAndLocal (-1) (-1)
    MethodCodeEnd

exportField : FieldExport -> Asm ()
exportField _ = Pure ()

exportClass : ClassExport -> Asm ()
exportClass (MkClassExport name idrisName extends implements modifiers annotations) = do
  CreateClass [ComputeMaxs, ComputeFrames]
  ClassCodeStart 52 modifiers name Nothing extends implements annotations

exportMemberIo : AsmGlobalState -> ExportDescriptor -> IO ()
exportMemberIo globalState (MkMethodExportDescriptor desc) = do
  asmState <- createAsmStateJavaName globalState desc.encloser.name
  ignore $ asm asmState $ exportFunction desc
exportMemberIo globalState (MkFieldExportDescriptor desc) = do
  asmState <- createAsmStateJavaName globalState desc.encloser.name
  ignore $ asm asmState $ exportField desc
exportMemberIo globalState (MkClassExportDescriptor desc) = do
  asmState <- createAsmStateJavaName globalState desc.name
  ignore $ asm asmState $ exportClass desc
exportMemberIo _ _ = pure ()

substituteTypeName : SortedMap String String -> String -> String
substituteTypeName imports type = fromMaybe type $ SortedMap.lookup type imports

substituteType : SortedMap String String -> InferredType -> InferredType
substituteType imports ref@(IRef type refType) = maybe ref (flip IRef refType) $ SortedMap.lookup type imports
substituteType imports ref@(IArray (IRef type refType)) =
  maybe ref (IArray . (flip IRef refType)) $ SortedMap.lookup type imports
substituteType imports ref@(IArray (IArray type)) = IArray (IArray $ substituteType imports type)
substituteType imports type = type

substituteFunctionType : SortedMap String String -> InferredFunctionType -> InferredFunctionType
substituteFunctionType imports (MkInferredFunctionType returnType argumentTypes) =
  let updatedReturnType = substituteType imports returnType
      updatedArgumentTypes = (substituteType imports) <$> argumentTypes
  in MkInferredFunctionType updatedReturnType updatedArgumentTypes

mutual
  substituteAnnotationValue : SortedMap String String -> AnnotationValue -> AnnotationValue
  substituteAnnotationValue imports (AnnAnnotation annotation) = AnnAnnotation (substituteAnnotation imports annotation)
  substituteAnnotationValue imports (AnnArray values) = AnnArray (substituteAnnotationValue imports <$> values)
  substituteAnnotationValue imports (AnnEnum type value) = AnnEnum (substituteTypeName imports type) value
  substituteAnnotationValue imports (AnnClass value) = AnnClass (substituteTypeName imports value)
  substituteAnnotationValue _ value = value

  substituteAnnotationProperty : SortedMap String String -> AnnotationProperty -> AnnotationProperty
  substituteAnnotationProperty imports (name, value) = (name, substituteAnnotationValue imports value)

  substituteAnnotation : SortedMap String String -> Annotation -> Annotation
  substituteAnnotation imports (MkAnnotation name props) =
    MkAnnotation (substituteTypeName imports name) (substituteAnnotationProperty imports <$> props)

findImports : SortedMap Namespace (SortedMap String String) -> Name -> Maybe (SortedMap String String)
findImports functionImports name = go (sortBy comparingNamespaceLength parents) where

    parents : List Namespace
    parents = allParents $ getNamespace name

    comparingNamespaceLength : Namespace -> Namespace -> Ordering
    comparingNamespaceLength = comparing (negate . cast {to=Int} . String.length . show)

    go : List Namespace -> Maybe (SortedMap String String)
    go [] = Nothing
    go (ns :: rest) = maybe (go rest) Just $ SortedMap.lookup ns functionImports

substituteClassExport : SortedMap Namespace (SortedMap String String) -> ClassExport -> ClassExport
substituteClassExport functionImports desc = case findImports functionImports desc.idrisName of
  Nothing => desc
  Just imports =>
    let
      updatedName = substituteTypeName imports desc.name
      updatedExtends = substituteTypeName imports desc.extends
      updatedImplements = substituteTypeName imports <$> desc.implements
      updatedAnnotations = substituteAnnotation imports <$> desc.annotations
    in MkClassExport updatedName desc.idrisName updatedExtends updatedImplements desc.modifiers updatedAnnotations

substituteImport : SortedMap Namespace (SortedMap String String) -> ExportDescriptor -> ExportDescriptor
substituteImport functionImports exportDesc@(MkMethodExportDescriptor desc) =
  case findImports functionImports desc.idrisName of
    Nothing => exportDesc
    Just imports =>
      let
        updatedType = substituteFunctionType imports desc.type
        updatedEncloser = substituteClassExport functionImports desc.encloser
        updatedAnnotations = substituteAnnotation imports <$> desc.annotations
        updatedParameterAnnotations = (substituteAnnotation imports <$>) <$> desc.parameterAnnotations
      in MkMethodExportDescriptor $ MkMethodExport desc.name desc.idrisName updatedType updatedEncloser desc.modifiers
           updatedAnnotations updatedParameterAnnotations
substituteImport functionImports exportDesc@(MkFieldExportDescriptor desc) =
  case findImports functionImports desc.idrisName of
    Nothing => exportDesc
    Just imports =>
      let
        updatedType = substituteType imports desc.type
        updatedAnnotations = substituteAnnotation imports <$> desc.annotations
        updatedEncloser = substituteClassExport functionImports desc.encloser
      in MkFieldExportDescriptor $ MkFieldExport desc.name desc.idrisName updatedType updatedEncloser desc.modifiers
           updatedAnnotations
substituteImport functionImports (MkClassExportDescriptor desc) =
  MkClassExportDescriptor $ substituteClassExport functionImports desc
substituteImport _ desc = desc

substituteImports : SortedMap Namespace (SortedMap String String) -> List ExportDescriptor -> List ExportDescriptor
substituteImports imports descriptors = (substituteImport imports) <$> descriptors

parseExportDescriptors : AsmGlobalState -> List (Name, String) -> IO (List ExportDescriptor)
parseExportDescriptors globalState descriptors = do
    (imports, exportDescriptors) <- go (SortedMap.empty, []) descriptors
    pure $ substituteImports imports $ sortBy (comparing memberTypeOrder) exportDescriptors
  where
    memberTypeOrder : ExportDescriptor -> Nat
    memberTypeOrder (MkClassExportDescriptor _) = 0
    memberTypeOrder (MkFieldExportDescriptor fieldExport) = if Static `elem` fieldExport.modifiers then 1 else 2
    memberTypeOrder (MkMethodExportDescriptor _) = 3
    memberTypeOrder _ = 4

    go : (SortedMap Namespace (SortedMap String String), List ExportDescriptor) ->
            List (Name, String) -> IO (SortedMap Namespace (SortedMap String String), List ExportDescriptor)
    go acc [] = pure acc
    go (imports, descriptors) ((idrisName, descriptor) :: rest) = do
      asmState <- createAsmState globalState idrisName
      (exportDescriptor, _) <- asm asmState (parseExportDescriptor idrisName descriptor)
      case exportDescriptor of
        MkImportDescriptor name currentImports =>
          let newImports = SortedMap.merge imports (SortedMap.singleton (getNamespace name) currentImports)
          in go (newImports, descriptors) rest
        _ => go (imports, exportDescriptor :: descriptors) rest

export
exportDefs : AsmGlobalState -> List (Name, String) -> IO ()
exportDefs globalState nameAndDescriptors = do
  descriptors <- parseExportDescriptors globalState nameAndDescriptors
  traverse_ (exportMemberIo globalState) descriptors

export
getExport : NoMangleMap -> Name -> Maybe (Name, String)
getExport noMangleMap name = (\descriptor => (name, descriptor)) <$> isNoMangle noMangleMap name