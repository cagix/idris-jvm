module Idris.REPL

import Compiler.Scheme.Chez
import Compiler.Scheme.Racket
import Compiler.Scheme.Gambit
import Compiler.ES.Node
import Compiler.ES.Javascript
import Compiler.Jvm.Codegen
import Compiler.Common
import Compiler.RefC.RefC

import Core.AutoSearch
import Core.CaseTree
import Core.CompileExpr
import Core.Context
import Core.Context.Log
import Core.Env
import Core.InitPrimitives
import Core.LinearCheck
import Core.Metadata
import Core.Normalise
import Core.Options
import Core.Termination
import Core.TT
import Core.Unify

import Parser.Unlit

import Idris.Desugar
import Idris.DocString
import Idris.Error
import Idris.IDEMode.CaseSplit
import Idris.IDEMode.Commands
import Idris.IDEMode.MakeClause
import Idris.IDEMode.Holes
import Idris.ModTree
import Idris.Parser
import Idris.Pretty
import Idris.ProcessIdr
import Idris.Resugar
import public Idris.REPLCommon
import Idris.Syntax
import Idris.Version

import TTImp.Elab
import TTImp.Elab.Check
import TTImp.Interactive.CaseSplit
import TTImp.Interactive.ExprSearch
import TTImp.Interactive.GenerateDef
import TTImp.Interactive.MakeLemma
import TTImp.TTImp
import TTImp.ProcessDecls

import Data.List
import Data.Maybe
import Data.NameMap
import Data.Stream
import Data.Strings
import Text.PrettyPrint.Prettyprinter
import Text.PrettyPrint.Prettyprinter.Util
import Text.PrettyPrint.Prettyprinter.Render.Terminal

import System
import System.File

%default covering

showInfo : {auto c : Ref Ctxt Defs} ->
           (Name, Int, GlobalDef) -> Core ()
showInfo (n, idx, d)
    = do coreLift $ putStrLn (show (fullname d) ++ " ==> " ++
                              show !(toFullNames (definition d)))
         coreLift $ putStrLn (show (multiplicity d))
         coreLift $ putStrLn ("Erasable args: " ++ show (eraseArgs d))
         coreLift $ putStrLn ("Detaggable arg types: " ++ show (safeErase d))
         coreLift $ putStrLn ("Specialise args: " ++ show (specArgs d))
         coreLift $ putStrLn ("Inferrable args: " ++ show (inferrable d))
         case compexpr d of
              Nothing => pure ()
              Just expr => coreLift $ putStrLn ("Compiled: " ++ show expr)
         coreLift $ putStrLn ("Refers to: " ++
                               show !(traverse getFullName (keys (refersTo d))))
         coreLift $ putStrLn ("Refers to (runtime): " ++
                               show !(traverse getFullName (keys (refersToRuntime d))))
         coreLift $ putStrLn ("Flags: " ++ show (flags d))
         when (not (isNil (sizeChange d))) $
            let scinfo = map (\s => show (fnCall s) ++ ": " ++
                                    show (fnArgs s)) !(traverse toFullNames (sizeChange d)) in
                coreLift $ putStrLn $
                        "Size change: " ++ showSep ", " scinfo

displayType : {auto c : Ref Ctxt Defs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              Defs -> (Name, Int, GlobalDef) ->
              Core (Doc IdrisAnn)
displayType defs (n, i, gdef)
    = maybe (do tm <- resugar [] !(normaliseHoles defs [] (type gdef))
                pure (pretty !(aliasName (fullname gdef)) <++> colon <++> prettyTerm tm))
            (\num => prettyHole defs [] n num (type gdef))
            (isHole gdef)

getEnvTerm : {vars : _} ->
             List Name -> Env Term vars -> Term vars ->
             (vars' ** (Env Term vars', Term vars'))
getEnvTerm (n :: ns) env (Bind fc x b sc)
    = if n == x
         then getEnvTerm ns (b :: env) sc
         else (_ ** (env, Bind fc x b sc))
getEnvTerm _ env tm = (_ ** (env, tm))

displayTerm : {auto c : Ref Ctxt Defs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              Defs -> ClosedTerm ->
              Core (Doc IdrisAnn)
displayTerm defs tm
    = do ptm <- resugar [] !(normaliseHoles defs [] tm)
         pure (prettyTerm ptm)

displayPatTerm : {auto c : Ref Ctxt Defs} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 Defs -> ClosedTerm ->
                 Core String
displayPatTerm defs tm
    = do ptm <- resugarNoPatvars [] !(normaliseHoles defs [] tm)
         pure (show ptm)

displayClause : {auto c : Ref Ctxt Defs} ->
                {auto s : Ref Syn SyntaxInfo} ->
                Defs -> (vs ** (Env Term vs, Term vs, Term vs)) ->
                Core (Doc IdrisAnn)
displayClause defs (vs ** (env, lhs, rhs))
    = do lhstm <- resugar env !(normaliseHoles defs env lhs)
         rhstm <- resugar env !(normaliseHoles defs env rhs)
         pure (prettyTerm lhstm <++> equals <++> prettyTerm rhstm)

displayPats : {auto c : Ref Ctxt Defs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              Defs -> (Name, Int, GlobalDef) ->
              Core (Doc IdrisAnn)
displayPats defs (n, idx, gdef)
    = case definition gdef of
           PMDef _ _ _ _ pats
               => do ty <- displayType defs (n, idx, gdef)
                     ps <- traverse (displayClause defs) pats
                     pure (vsep (ty :: ps))
           _ => pure (pretty n <++> reflow "is not a pattern matching definition")

setOpt : {auto c : Ref Ctxt Defs} ->
         {auto o : Ref ROpts REPLOpts} ->
         REPLOpt -> Core ()
setOpt (ShowImplicits t)
    = do pp <- getPPrint
         setPPrint (record { showImplicits = t } pp)
setOpt (ShowNamespace t)
    = do pp <- getPPrint
         setPPrint (record { fullNamespace = t } pp)
setOpt (ShowTypes t)
    = do opts <- get ROpts
         put ROpts (record { showTypes = t } opts)
setOpt (EvalMode m)
    = do opts <- get ROpts
         put ROpts (record { evalMode = m } opts)
setOpt (Editor e)
    = do opts <- get ROpts
         put ROpts (record { editor = e } opts)
setOpt (CG e)
    = do defs <- get Ctxt
         case getCG (options defs) e of
            Just cg => setCG cg
            Nothing => iputStrLn (reflow "No such code generator available")

getOptions : {auto c : Ref Ctxt Defs} ->
         {auto o : Ref ROpts REPLOpts} ->
         Core (List REPLOpt)
getOptions = do
  pp <- getPPrint
  opts <- get ROpts
  pure $ [ ShowImplicits (showImplicits pp), ShowNamespace (fullNamespace pp)
         , ShowTypes (showTypes opts), EvalMode (evalMode opts)
         , Editor (editor opts)
         ]

export
findCG : {auto o : Ref ROpts REPLOpts} ->
         {auto c : Ref Ctxt Defs} -> Core Codegen
findCG
    = do defs <- get Ctxt
         case codegen (session (options defs)) of
              Chez => pure codegenChez
              Racket => pure codegenRacket
              Gambit => pure codegenGambit
              Node => pure codegenNode
              Javascript => pure codegenJavascript
              RefC => pure codegenRefC
              Jvm => pure codegenJvm
              Other s => case !(getCodegen s) of
                            Just cg => pure cg
                            Nothing => do coreLift $ putStrLn ("No such code generator: " ++ s)
                                          coreLift $ exitWith (ExitFailure 1)

anyAt : (FC -> Bool) -> FC -> a -> Bool
anyAt p loc y = p loc

printClause : {auto c : Ref Ctxt Defs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              Maybe String -> Nat -> ImpClause ->
              Core String
printClause l i (PatClause _ lhsraw rhsraw)
    = do lhs <- pterm lhsraw
         rhs <- pterm rhsraw
         pure (relit l (pack (replicate i ' ') ++ show lhs ++ " = " ++ show rhs))
printClause l i (WithClause _ lhsraw wvraw flags csraw)
    = do lhs <- pterm lhsraw
         wval <- pterm wvraw
         cs <- traverse (printClause l (i + 2)) csraw
         pure ((relit l ((pack (replicate i ' ') ++ show lhs ++ " with (" ++ show wval ++ ")\n")) ++
                 showSep "\n" cs))
printClause l i (ImpossibleClause _ lhsraw)
    = do lhs <- pterm lhsraw
         pure (relit l (pack (replicate i ' ') ++ show lhs ++ " impossible"))


lookupDefTyName : Name -> Context ->
                  Core (List (Name, Int, (Def, ClosedTerm)))
lookupDefTyName = lookupNameBy (\g => (definition g, type g))

public export
data EditResult : Type where
  DisplayEdit : Doc IdrisAnn -> EditResult
  EditError : Doc IdrisAnn -> EditResult
  MadeLemma : Maybe String -> Name -> PTerm -> String -> EditResult
  MadeWith : Maybe String -> List String -> EditResult
  MadeCase : Maybe String -> List String -> EditResult

updateFile : {auto r : Ref ROpts REPLOpts} ->
             (List String -> List String) -> Core EditResult
updateFile update
    = do opts <- get ROpts
         let Just f = mainfile opts
             | Nothing => pure (DisplayEdit emptyDoc) -- no file, nothing to do
         Right content <- coreLift $ readFile f
               | Left err => throw (FileErr f err)
         coreLift $ writeFile (f ++ "~") content
         coreLift $ writeFile f (unlines (update (lines content)))
         pure (DisplayEdit emptyDoc)

rtrim : String -> String
rtrim str = reverse (ltrim (reverse str))

addClause : String -> Nat -> List String -> List String
addClause c Z [] = rtrim c :: []
addClause c Z (x :: xs)
    = if all isSpace (unpack x)
         then rtrim c :: x :: xs
         else x :: addClause c Z xs
addClause c (S k) (x :: xs) = x :: addClause c k xs
addClause c (S k) [] = [c]

caseSplit : String -> Nat -> List String -> List String
caseSplit c Z (x :: xs) = rtrim c :: xs
caseSplit c (S k) (x :: xs) = x :: caseSplit c k xs
caseSplit c _ [] = [c]

proofSearch : Name -> String -> Nat -> List String -> List String
proofSearch n res Z (x :: xs) = replaceStr ("?" ++ show n) res x :: xs
  where
    replaceStr : String -> String -> String -> String
    replaceStr rep new "" = ""
    replaceStr rep new str
        = if isPrefixOf rep str
             then new ++ pack (drop (length rep) (unpack str))
             else assert_total $ strCons (prim__strHead str)
                          (replaceStr rep new (prim__strTail str))
proofSearch n res (S k) (x :: xs) = x :: proofSearch n res k xs
proofSearch n res _ [] = []

addMadeLemma : Maybe String -> Name -> String -> String -> Nat -> List String -> List String
addMadeLemma lit n ty app line content
    = addApp lit line [] (proofSearch n app line content)
  where
    -- Put n : ty in the first blank line
    insertInBlank : Maybe String -> List String -> List String
    insertInBlank lit [] = [relit lit $ show n ++ " : " ++ ty ++ "\n"]
    insertInBlank lit (x :: xs)
        = if trim x == ""
             then ("\n" ++ (relit lit $ show n ++ " : " ++ ty ++ "\n")) :: xs
             else x :: insertInBlank lit xs

    addApp : Maybe String -> Nat -> List String -> List String -> List String
    addApp lit Z acc rest = reverse (insertInBlank lit acc) ++ rest
    addApp lit (S k) acc (x :: xs) = addApp lit k (x :: acc) xs
    addApp _ (S k) acc [] = reverse acc

-- Replace a line; works for 'case' and 'with'
addMadeCase : Maybe String -> List String -> Nat -> List String -> List String
addMadeCase lit wapp line content
    = addW line [] content
  where
    addW : Nat -> List String -> List String -> List String
    addW Z acc (_ :: rest) = reverse acc ++ map (relit lit) wapp ++ rest
    addW Z acc [] = [] -- shouldn't happen!
    addW (S k) acc (x :: xs) = addW k (x :: acc) xs
    addW (S k) acc [] = reverse acc

nextProofSearch : {auto c : Ref Ctxt Defs} ->
                  {auto u : Ref UST UState} ->
                  {auto o : Ref ROpts REPLOpts} ->
                  Core (Maybe (Name, RawImp))
nextProofSearch
    = do opts <- get ROpts
         let Just (n, res) = psResult opts
              | Nothing => pure Nothing
         Just (res, next) <- nextResult res
              | Nothing =>
                    do put ROpts (record { psResult = Nothing } opts)
                       pure Nothing
         put ROpts (record { psResult = Just (n, next) } opts)
         pure (Just (n, res))

nextGenDef : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto o : Ref ROpts REPLOpts} ->
             (reject : Nat) ->
             Core (Maybe (Int, (FC, List ImpClause)))
nextGenDef reject
    = do opts <- get ROpts
         let Just (line, res) = gdResult opts
              | Nothing => pure Nothing
         Just (res, next) <- nextResult res
              | Nothing =>
                    do put ROpts (record { gdResult = Nothing } opts)
                       pure Nothing
         put ROpts (record { gdResult = Just (line, next) } opts)
         case reject of
              Z => pure (Just (line, res))
              S k => nextGenDef k

dropLams : Nat -> RawImp -> RawImp
dropLams Z tm = tm
dropLams (S k) (ILam _ _ _ _ _ sc) = dropLams k sc
dropLams _ tm = tm

dropLamsTm : {vars : _} ->
             Nat -> Env Term vars -> Term vars ->
             (vars' ** (Env Term vars', Term vars'))
dropLamsTm Z env tm = (_ ** (env, tm))
dropLamsTm (S k) env (Bind _ _ b sc) = dropLamsTm k (b :: env) sc
dropLamsTm _ env tm = (_ ** (env, tm))

processEdit : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto m : Ref MD Metadata} ->
              {auto o : Ref ROpts REPLOpts} ->
              EditCmd -> Core EditResult
processEdit (TypeAt line col name)
    = do defs <- get Ctxt
         glob <- lookupCtxtName name (gamma defs)
         res <- the (Core (Doc IdrisAnn)) $ case glob of
                     [] => pure emptyDoc
                     ts => do tys <- traverse (displayType defs) ts
                              pure (vsep tys)
         Just (n, num, t) <- findTypeAt (\p, n => within (line-1, col-1) p)
            | Nothing => case res of
                              Empty => throw (UndefinedName (MkFC "(interactive)" (0,0) (0,0)) name)
                              _     => pure (DisplayEdit res)
         case res of
            Empty => pure (DisplayEdit $ pretty (nameRoot n) <++> colon <++> !(displayTerm defs t))
            _     => pure (DisplayEdit emptyDoc)  -- ? Why () This means there is a global name and a type at (line,col)
processEdit (CaseSplit upd line col name)
    = do let find = if col > 0
                       then within (line-1, col-1)
                       else onLine (line-1)
         OK splits <- getSplits (anyAt find) name
             | SplitFail err => pure (EditError (pretty $ show err))
         lines <- updateCase splits (line-1) (col-1)
         if upd
            then updateFile (caseSplit (unlines lines) (integerToNat (cast (line - 1))))
            else pure $ DisplayEdit (vsep $ pretty <$> lines)
processEdit (AddClause upd line name)
    = do Just c <- getClause line name
             | Nothing => pure (EditError (pretty name <++> reflow "not defined here"))
         if upd
            then updateFile (addClause c (integerToNat (cast line)))
            else pure $ DisplayEdit (pretty c)
processEdit (ExprSearch upd line name hints)
    = do defs <- get Ctxt
         syn <- get Syn
         let brack = elemBy (\x, y => dropNS x == dropNS y) name (bracketholes syn)
         case !(lookupDefName name (gamma defs)) of
              [(n, nidx, Hole locs _)] =>
                  do let searchtm = exprSearch replFC name []
                     ropts <- get ROpts
                     put ROpts (record { psResult = Just (name, searchtm) } ropts)
                     defs <- get Ctxt
                     Just (_, restm) <- nextProofSearch
                          | Nothing => pure $ EditError "No search results"
                     let tm' = dropLams locs restm
                     itm <- pterm tm'
                     let itm' : PTerm = if brack then addBracket replFC itm else itm
                     if upd
                        then updateFile (proofSearch name (show itm') (integerToNat (cast (line - 1))))
                        else pure $ DisplayEdit (prettyTerm itm')
              [(n, nidx, PMDef pi [] (STerm _ tm) _ _)] =>
                  case holeInfo pi of
                       NotHole => pure $ EditError "Not a searchable hole"
                       SolvedHole locs =>
                          do let (_ ** (env, tm')) = dropLamsTm locs [] tm
                             itm <- resugar env tm'
                             let itm' : PTerm = if brack then addBracket replFC itm else itm
                             if upd
                                then updateFile (proofSearch name (show itm') (integerToNat (cast (line - 1))))
                                else pure $ DisplayEdit (prettyTerm itm')
              [] => pure $ EditError $ "Unknown name" <++> pretty name
              _ => pure $ EditError "Not a searchable hole"
processEdit ExprSearchNext
    = do defs <- get Ctxt
         syn <- get Syn
         Just (name, restm) <- nextProofSearch
              | Nothing => pure $ EditError "No more results"
         [(n, nidx, Hole locs _)] <- lookupDefName name (gamma defs)
              | _ => pure $ EditError "Not a searchable hole"
         let brack = elemBy (\x, y => dropNS x == dropNS y) name (bracketholes syn)
         let tm' = dropLams locs restm
         itm <- pterm tm'
         let itm' : PTerm = if brack then addBracket replFC itm else itm
         pure $ DisplayEdit (prettyTerm itm')

processEdit (GenerateDef upd line name rej)
    = do defs <- get Ctxt
         Just (_, n', _, _) <- findTyDeclAt (\p, n => onLine (line - 1) p)
             | Nothing => pure (EditError ("Can't find declaration for" <++> pretty name <++> "on line" <++> pretty line))
         case !(lookupDefExact n' (gamma defs)) of
              Just None =>
                 do let searchdef = makeDefSort (\p, n => onLine (line - 1) p)
                                                16 mostUsed n'
                    ropts <- get ROpts
                    put ROpts (record { gdResult = Just (line, searchdef) } ropts)
                    Just (_, (fc, cs)) <- nextGenDef rej
                         | Nothing => pure (EditError "No search results")
                    let l : Nat =  integerToNat (cast (snd (startPos fc)))
                    Just srcLine <- getSourceLine line
                       | Nothing => pure (EditError "Source line not found")
                    let (markM, srcLineUnlit) = isLitLine srcLine
                    ls <- traverse (printClause markM l) cs
                    if upd
                       then updateFile (addClause (unlines ls) (integerToNat (cast line)))
                       else pure $ DisplayEdit (vsep $ pretty <$> ls)
              Just _ => pure $ EditError "Already defined"
              Nothing => pure $ EditError $ "Can't find declaration for" <++> pretty name
processEdit GenerateDefNext
    = do Just (line, (fc, cs)) <- nextGenDef 0
              | Nothing => pure (EditError "No more results")
         let l : Nat =  integerToNat (cast (snd (startPos fc)))
         Just srcLine <- getSourceLine line
            | Nothing => pure (EditError "Source line not found")
         let (markM, srcLineUnlit) = isLitLine srcLine
         ls <- traverse (printClause markM l) cs
         pure $ DisplayEdit (vsep $ pretty <$> ls)
processEdit (MakeLemma upd line name)
    = do defs <- get Ctxt
         syn <- get Syn
         let brack = elemBy (\x, y => dropNS x == dropNS y) name (bracketholes syn)
         case !(lookupDefTyName name (gamma defs)) of
              [(n, nidx, Hole locs _, ty)] =>
                  do (lty, lapp) <- makeLemma replFC name locs ty
                     pty <- pterm lty
                     papp <- pterm lapp
                     opts <- get ROpts
                     let pappstr = show (the PTerm (if brack
                                            then addBracket replFC papp
                                            else papp))
                     Just srcLine <- getSourceLine line
                       | Nothing => pure (EditError "Source line not found")
                     let (markM,_) = isLitLine srcLine
                     if upd
                        then updateFile (addMadeLemma markM name (show pty) pappstr
                                                      (max 0 (integerToNat (cast (line - 1)))))
                        else pure $ MadeLemma markM name pty pappstr
              _ => pure $ EditError "Can't make lifted definition"
processEdit (MakeCase upd line name)
    = do litStyle <- getLitStyle
         syn <- get Syn
         let brack = elemBy (\x, y => dropNS x == dropNS y) name (bracketholes syn)
         Just src <- getSourceLine line
              | Nothing => pure (EditError "Source line not available")
         let Right l = unlit litStyle src
              | Left err => pure (EditError "Invalid literate Idris")
         let (markM, _) = isLitLine src
         let c = lines $ makeCase brack name l
         if upd
            then updateFile (addMadeCase markM c (max 0 (integerToNat (cast (line - 1)))))
            else pure $ MadeCase markM c
processEdit (MakeWith upd line name)
    = do litStyle <- getLitStyle
         Just src <- getSourceLine line
              | Nothing => pure (EditError "Source line not available")
         let Right l = unlit litStyle src
              | Left err => pure (EditError "Invalid literate Idris")
         let (markM, _) = isLitLine src
         let w = lines $ makeWith name l
         if upd
            then updateFile (addMadeCase markM w (max 0 (integerToNat (cast (line - 1)))))
            else pure $ MadeWith markM w

public export
data MissedResult : Type where
  CasesMissing : Name -> List String  -> MissedResult
  CallsNonCovering : Name -> List Name -> MissedResult
  AllCasesCovered : Name -> MissedResult

public export
data REPLResult : Type where
  Done : REPLResult
  REPLError : Doc IdrisAnn -> REPLResult
  Executed : PTerm -> REPLResult
  RequestedHelp : REPLResult
  Evaluated : PTerm -> (Maybe PTerm) -> REPLResult
  Printed : Doc IdrisAnn -> REPLResult
  TermChecked : PTerm -> PTerm -> REPLResult
  FileLoaded : String -> REPLResult
  ModuleLoaded : String -> REPLResult
  ErrorLoadingModule : String -> Error -> REPLResult
  ErrorLoadingFile : String -> FileError -> REPLResult
  ErrorsBuildingFile : String -> List Error -> REPLResult
  NoFileLoaded : REPLResult
  CurrentDirectory : String -> REPLResult
  CompilationFailed: REPLResult
  Compiled : String -> REPLResult
  ProofFound : PTerm -> REPLResult
  Missed : List MissedResult -> REPLResult
  CheckedTotal : List (Name, Totality) -> REPLResult
  FoundHoles : List HoleData -> REPLResult
  OptionsSet : List REPLOpt -> REPLResult
  LogLevelSet : Maybe LogLevel -> REPLResult
  ConsoleWidthSet : Maybe Nat -> REPLResult
  ColorSet : Bool -> REPLResult
  VersionIs : Version -> REPLResult
  DefDeclared : REPLResult
  Exited : REPLResult
  Edited : EditResult -> REPLResult

export
execExp : {auto c : Ref Ctxt Defs} ->
          {auto u : Ref UST UState} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto m : Ref MD Metadata} ->
          {auto o : Ref ROpts REPLOpts} ->
          PTerm -> Core REPLResult
execExp ctm
    = do ttimp <- desugar AnyExpr [] (PApp replFC (PRef replFC (UN "unsafePerformIO")) ctm)
         inidx <- resolveName (UN "[input]")
         (tm, ty) <- elabTerm inidx InExpr [] (MkNested [])
                                 [] ttimp Nothing
         tm_erased <- linearCheck replFC linear True [] tm
         execute !findCG tm_erased
         pure $ Executed ctm


execDecls : {auto c : Ref Ctxt Defs} ->
            {auto u : Ref UST UState} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto m : Ref MD Metadata} ->
            List PDecl -> Core REPLResult
execDecls decls = do
  traverse_ execDecl decls
  pure DefDeclared
  where
    execDecl : PDecl -> Core ()
    execDecl decl = do
      i <- desugarDecl [] decl
      traverse_ (processDecl [] (MkNested []) []) i

export
compileExp : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto m : Ref MD Metadata} ->
             {auto o : Ref ROpts REPLOpts} ->
             PTerm -> String -> Core REPLResult
compileExp ctm outfile
    = do inidx <- resolveName (UN "[input]")
         ttimp <- desugar AnyExpr [] (PApp replFC (PRef replFC (UN "unsafePerformIO")) ctm)
         (tm, gty) <- elabTerm inidx InExpr [] (MkNested [])
                               [] ttimp Nothing
         tm_erased <- linearCheck replFC linear True [] tm
         ok <- compile !findCG tm_erased outfile
         maybe (pure CompilationFailed)
               (pure . Compiled)
               ok

export
loadMainFile : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto m : Ref MD Metadata} ->
               {auto o : Ref ROpts REPLOpts} ->
               String -> Core REPLResult
loadMainFile f
    = do resetContext
         Right res <- coreLift (readFile f)
            | Left err => do setSource ""
                             pure (ErrorLoadingFile f err)
         errs <- logTime "+ Build deps" $ buildDeps f
         updateErrorLine errs
         setSource res
         resetProofState
         case errs of
           [] => pure (FileLoaded f)
           _ => pure (ErrorsBuildingFile f errs)


||| Process a single `REPLCmd`
|||
||| Returns `REPLResult` for display by the higher level shell which
||| is invoking this interactive command processing.
export
process : {auto c : Ref Ctxt Defs} ->
          {auto u : Ref UST UState} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto m : Ref MD Metadata} ->
          {auto o : Ref ROpts REPLOpts} ->
          REPLCmd -> Core REPLResult
process (NewDefn decls) = execDecls decls
process (Eval itm)
    = do opts <- get ROpts
         case evalMode opts of
            Execute => do execExp itm; pure (Executed itm)
            _ =>
              do ttimp <- desugar AnyExpr [] itm
                 inidx <- resolveName (UN "[input]")
                 -- a TMP HACK to prioritise list syntax for List: hide
                 -- foreign argument lists. TODO: once the new FFI is fully
                 -- up and running we won't need this. Also, if we add
                 -- 'with' disambiguation we can use that instead.
                 catch (do hide replFC (NS primIONS (UN "::"))
                           hide replFC (NS primIONS (UN "Nil")))
                       (\err => pure ())
                 (tm, gty) <- elabTerm inidx (emode (evalMode opts)) [] (MkNested [])
                                       [] ttimp Nothing
                 logTerm "repl.eval" 10 "Elaborated input" tm
                 defs <- get Ctxt
                 opts <- get ROpts
                 let norm = nfun (evalMode opts)
                 ntm <- norm defs [] tm
                 logTermNF "repl.eval" 5 "Normalised" [] ntm
                 itm <- resugar [] ntm
                 ty <- getTerm gty
                 addDef (UN "it") (newDef emptyFC (UN "it") top [] ty Private (PMDef defaultPI [] (STerm 0 ntm) (STerm 0 ntm) []))
                 if showTypes opts
                    then do ity <- resugar [] !(norm defs [] ty)
                            pure (Evaluated itm (Just ity))
                    else pure (Evaluated itm Nothing)
  where
    emode : REPLEval -> ElabMode
    emode EvalTC = InType
    emode _ = InExpr

    nfun : {vs : _} ->
           REPLEval -> Defs -> Env Term vs -> Term vs -> Core (Term vs)
    nfun NormaliseAll = normaliseAll
    nfun _ = normalise
process (Check (PRef fc fn))
    = do defs <- get Ctxt
         case !(lookupCtxtName fn (gamma defs)) of
              [] => throw (UndefinedName fc fn)
              ts => do tys <- traverse (displayType defs) ts
                       pure (Printed $ vsep tys)
process (Check itm)
    = do inidx <- resolveName (UN "[input]")
         ttimp <- desugar AnyExpr [] itm
         (tm, gty) <- elabTerm inidx InExpr [] (MkNested [])
                                  [] ttimp Nothing
         defs <- get Ctxt
         itm <- resugar [] !(normaliseHoles defs [] tm)
         ty <- getTerm gty
         ity <- resugar [] !(normaliseScope defs [] ty)
         pure (TermChecked itm ity)
process (PrintDef fn)
    = do defs <- get Ctxt
         case !(lookupCtxtName fn (gamma defs)) of
              [] => throw (UndefinedName replFC fn)
              ts => do defs <- traverse (displayPats defs) ts
                       pure (Printed $ vsep defs)
process Reload
    = do opts <- get ROpts
         case mainfile opts of
              Nothing => pure NoFileLoaded
              Just f => loadMainFile f
process (Load f)
    = do opts <- get ROpts
         put ROpts (record { mainfile = Just f } opts)
         -- Clear the context and load again
         loadMainFile f
process (ImportMod m)
    = do catch (do addImport (MkImport emptyFC False m (miAsNamespace m))
                   pure $ ModuleLoaded (show m))
               (\err => pure $ ErrorLoadingModule (show m) err)
process (CD dir)
    = do setWorkingDir dir
         workDir <- getWorkingDir
         pure (CurrentDirectory workDir)
process CWD
    = do workDir <- getWorkingDir
         pure (CurrentDirectory workDir)
process Edit
    = do opts <- get ROpts
         case mainfile opts of
              Nothing => pure NoFileLoaded
              Just f =>
                do let line = maybe "" (\i => " +" ++ show (i + 1)) (errorLine opts)
                   coreLift $ system (editor opts ++ " \"" ++ f ++ "\"" ++ line)
                   loadMainFile f
process (Compile ctm outfile)
    = compileExp ctm outfile
process (Exec ctm)
    = execExp ctm
process Help
    = pure RequestedHelp
process (ProofSearch n_in)
    = do defs <- get Ctxt
         [(n, i, ty)] <- lookupTyName n_in (gamma defs)
              | [] => throw (UndefinedName replFC n_in)
              | ns => throw (AmbiguousName replFC (map fst ns))
         tm <- search replFC top False 1000 n ty []
         itm <- resugar [] !(normaliseHoles defs [] tm)
         pure $ ProofFound itm
process (Missing n)
    = do defs <- get Ctxt
         case !(lookupCtxtName n (gamma defs)) of
              [] => throw (UndefinedName replFC n)
              ts => map Missed $ traverse (\fn =>
                                         do tot <- getTotality replFC fn
                                            the (Core MissedResult) $ case isCovering tot of
                                                 MissingCases cs =>
                                                    do tms <- traverse (displayPatTerm defs) cs
                                                       pure $ CasesMissing fn tms
                                                 NonCoveringCall ns_in =>
                                                   do ns <- traverse getFullName ns_in
                                                      pure $ CallsNonCovering fn ns
                                                 _ => pure $ AllCasesCovered fn)
                               (map fst ts)
process (Total n)
    = do defs <- get Ctxt
         case !(lookupCtxtName n (gamma defs)) of
              [] => throw (UndefinedName replFC n)
              ts => map CheckedTotal $
                    traverse (\fn =>
                          do checkTotal replFC fn
                             tot <- getTotality replFC fn >>= toFullNames
                             pure $ (fn, tot))
                               (map fst ts)
process (Doc n)
    = do doc <- getDocsFor replFC n
         pure $ Printed $ vsep $ pretty <$> doc
process (Browse ns)
    = do doc <- getContents ns
         pure $ Printed $ vsep $ pretty <$> doc
process (DebugInfo n)
    = do defs <- get Ctxt
         traverse_ showInfo !(lookupCtxtName n (gamma defs))
         pure Done
process (SetOpt opt)
    = do setOpt opt
         pure Done
process GetOpts
    = do opts <- getOptions
         pure $ OptionsSet opts
process (SetLog lvl)
    = do addLogLevel lvl
         pure $ LogLevelSet lvl
process (SetConsoleWidth n)
    = do setConsoleWidth n
         pure $ ConsoleWidthSet n
process (SetColor b)
    = do setColor b
         pure $ ColorSet b
process Metavars
    = do defs <- get Ctxt
         let ctxt = gamma defs
         ms  <- getUserHoles
         let globs = concat !(traverse (\n => lookupCtxtName n ctxt) ms)
         let holesWithArgs = mapMaybe (\(n, i, gdef) => do args <- isHole gdef
                                                           pure (n, gdef, args))
                                      globs
         hData <- the (Core $ List HoleData) $
             traverse (\n_gdef_args =>
                        -- Inference can't deal with this for now :/
                        let (n, gdef, args) = the (Name, GlobalDef, Nat) n_gdef_args in
                        holeData defs [] n args (type gdef))
                      holesWithArgs
         pure $ FoundHoles hData

process (Editing cmd)
    = do ppopts <- getPPrint
         -- Since we're working in a local environment, don't do the usual
         -- thing of printing out the full environment for parameterised
         -- calls or calls in where blocks
         setPPrint (record { showFullEnv = False } ppopts)
         res <- processEdit cmd
         setPPrint ppopts
         pure $ Edited res
process (CGDirective str)
    = do setSession (record { directives $= (str::) } !getSession)
         pure Done
process (RunShellCommand cmd)
    = do coreLift (system cmd)
         pure Done
process Quit
    = pure Exited
process NOP
    = pure Done
process ShowVersion
    = pure $ VersionIs  version

processCatch : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto m : Ref MD Metadata} ->
               {auto o : Ref ROpts REPLOpts} ->
               REPLCmd -> Core REPLResult
processCatch cmd
    = do c' <- branch
         u' <- get UST
         s' <- get Syn
         o' <- get ROpts
         catch (do r <- process cmd
                   commit
                   pure r)
               (\err => do put Ctxt c'
                           put UST u'
                           put Syn s'
                           put ROpts o'
                           msg <- display err
                           pure $ REPLError msg
                           )

parseEmptyCmd : SourceEmptyRule (Maybe REPLCmd)
parseEmptyCmd = eoi *> (pure Nothing)

parseCmd : SourceEmptyRule (Maybe REPLCmd)
parseCmd = do c <- command; eoi; pure $ Just c

export
parseRepl : String -> Either (ParseError Token) (Maybe REPLCmd)
parseRepl inp
    = case fnameCmd [(":load ", Load), (":l ", Load), (":cd ", CD), (":!", RunShellCommand)] inp of
           Nothing => runParser Nothing inp (parseEmptyCmd <|> parseCmd)
           Just cmd => Right $ Just cmd
  where
    -- a right load of hackery - we can't tokenise the filename using the
    -- ordinary parser. There's probably a better way...
    getLoad : Nat -> (String -> REPLCmd) -> String -> Maybe REPLCmd
    getLoad n cmd str = Just (cmd (trim (substr n (length str) str)))

    fnameCmd : List (String, String -> REPLCmd) -> String -> Maybe REPLCmd
    fnameCmd [] inp = Nothing
    fnameCmd ((pre, cmd) :: rest) inp
        = if isPrefixOf pre inp
             then getLoad (length pre) cmd inp
             else fnameCmd rest inp

export
interpret : {auto c : Ref Ctxt Defs} ->
            {auto u : Ref UST UState} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto m : Ref MD Metadata} ->
            {auto o : Ref ROpts REPLOpts} ->
            String -> Core REPLResult
interpret inp
    = case parseRepl inp of
           Left err => pure $ REPLError (pretty err)
           Right Nothing => pure Done
           Right (Just cmd) => do
             setCurrentElabSource inp
             processCatch cmd

mutual
  export
  replCmd : {auto c : Ref Ctxt Defs} ->
            {auto u : Ref UST UState} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto m : Ref MD Metadata} ->
            {auto o : Ref ROpts REPLOpts} ->
            String -> Core ()
  replCmd "" = pure ()
  replCmd cmd
      = do res <- interpret cmd
           displayResult res

  export
  repl : {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         {auto s : Ref Syn SyntaxInfo} ->
         {auto m : Ref MD Metadata} ->
         {auto o : Ref ROpts REPLOpts} ->
         Core ()
  repl
      = do ns <- getNS
           opts <- get ROpts
           coreLift (putStr (prompt (evalMode opts) ++ show ns ++ "> "))
           inp <- coreLift getLine
           end <- coreLift $ fEOF stdin
           if end
             then do
               -- start a new line in REPL mode (not relevant in IDE mode)
               coreLift $ putStrLn ""
               iputStrLn $ pretty "Bye for now!"
              else do res <- interpret inp
                      handleResult res

    where
      prompt : REPLEval -> String
      prompt EvalTC = "[tc] "
      prompt NormaliseAll = ""
      prompt Execute = "[exec] "

  export
  handleMissing' : MissedResult -> String
  handleMissing' (CasesMissing x xs) = show x ++ ":\n" ++ showSep "\n" xs
  handleMissing' (CallsNonCovering fn ns) = (show fn ++ ": Calls non covering function"
                                           ++ (case ns of
                                                 [f] => " " ++ show f
                                                 _ => "s: " ++ showSep ", " (map show ns)))
  handleMissing' (AllCasesCovered fn) = show fn ++ ": All cases covered"

  export
  handleMissing : MissedResult -> Doc IdrisAnn
  handleMissing (CasesMissing x xs) = pretty x <+> colon <++> vsep (code . pretty <$> xs)
  handleMissing (CallsNonCovering fn ns) =
    pretty fn <+> colon <++> reflow "Calls non covering"
      <++> (case ns of
                 [f] => "function" <++> code (pretty f)
                 _ => "functions:" <++> concatWith (surround (comma <+> space)) (code . pretty <$> ns))
  handleMissing (AllCasesCovered fn) = pretty fn <+> colon <++> reflow "All cases covered"

  export
  handleResult : {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         {auto s : Ref Syn SyntaxInfo} ->
         {auto m : Ref MD Metadata} ->
         {auto o : Ref ROpts REPLOpts} -> REPLResult -> Core ()
  handleResult Exited = iputStrLn (reflow "Bye for now!")
  handleResult other = do { displayResult other ; repl }

  export
  displayResult : {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         {auto s : Ref Syn SyntaxInfo} ->
         {auto m : Ref MD Metadata} ->
         {auto o : Ref ROpts REPLOpts} -> REPLResult -> Core ()
  displayResult (REPLError err) = printError err
  displayResult (Evaluated x Nothing) = printResult $ prettyTerm x
  displayResult (Evaluated x (Just y)) = printResult (prettyTerm x <++> colon <++> code (prettyTerm y))
  displayResult (Printed xs) = printResult xs
  displayResult (TermChecked x y) = printResult (prettyTerm x <++> colon <++> code (prettyTerm y))
  displayResult (FileLoaded x) = printResult (reflow "Loaded file" <++> pretty x)
  displayResult (ModuleLoaded x) = printResult (reflow "Imported module" <++> pretty x)
  displayResult (ErrorLoadingModule x err) = printResult (reflow "Error loading module" <++> pretty x <+> colon <++> !(perror err))
  displayResult (ErrorLoadingFile x err) = printResult (reflow "Error loading file" <++> pretty x <+> colon <++> pretty (show err))
  displayResult (ErrorsBuildingFile x errs) = printResult (reflow "Error(s) building file" <++> pretty x) -- messages already displayed while building
  displayResult NoFileLoaded = printError (reflow "No file can be reloaded")
  displayResult (CurrentDirectory dir) = printResult (reflow "Current working directory is" <++> squotes (pretty dir))
  displayResult CompilationFailed = printError (reflow "Compilation failed")
  displayResult (Compiled f) = printResult (pretty "File" <++> pretty f <++> pretty "written")
  displayResult (ProofFound x) = printResult (prettyTerm x)
  displayResult (Missed cases) = printResult $ vsep (handleMissing <$> cases)
  displayResult (CheckedTotal xs) = printResult (vsep (map (\(fn, tot) => pretty fn <++> pretty "is" <++> pretty tot) xs))
  displayResult (FoundHoles []) = printResult (reflow "No holes")
  displayResult (FoundHoles [x]) = printResult (reflow "1 hole" <+> colon <++> pretty x.name)
  displayResult (FoundHoles xs) = do
    let holes = concatWith (surround (pretty ", ")) (pretty . name <$> xs)
    printResult (pretty (length xs) <++> pretty "holes" <+> colon <++> holes)
  displayResult (LogLevelSet Nothing) = printResult (reflow "Logging turned off")
  displayResult (LogLevelSet (Just k)) = printResult (reflow "Set log level to" <++> pretty k)
  displayResult (ConsoleWidthSet (Just k)) = printResult (reflow "Set consolewidth to" <++> pretty k)
  displayResult (ConsoleWidthSet Nothing) = printResult (reflow "Set consolewidth to auto")
  displayResult (ColorSet b) = printResult (reflow (if b then "Set color on" else "Set color off"))
  displayResult (VersionIs x) = printResult (pretty (showVersion True x))
  displayResult (RequestedHelp) = printResult (pretty displayHelp)
  displayResult (Edited (DisplayEdit Empty)) = pure ()
  displayResult (Edited (DisplayEdit xs)) = printResult xs
  displayResult (Edited (EditError x)) = printError x
  displayResult (Edited (MadeLemma lit name pty pappstr)) = printResult $ pretty (relit lit (show name ++ " : " ++ show pty ++ "\n") ++ pappstr)
  displayResult (Edited (MadeWith lit wapp)) = printResult $ pretty $ showSep "\n" (map (relit lit) wapp)
  displayResult (Edited (MadeCase lit cstr)) = printResult $ pretty $ showSep "\n" (map (relit lit) cstr)
  displayResult (OptionsSet opts) = printResult (vsep (pretty <$> opts))
  displayResult _ = pure ()

  export
  displayHelp : String
  displayHelp =
    showSep "\n" $ map cmdInfo help
    where
      makeSpace : Nat -> String
      makeSpace n = pack $ take n (repeat ' ')

      col : Nat -> Nat -> String -> String -> String -> String
      col c1 c2 l m r =
        l ++ (makeSpace $ c1 `minus` length l) ++
        m ++ (makeSpace $ c2 `minus` length m) ++ r

      cmdInfo : (List String, CmdArg, String) -> String
      cmdInfo (cmds, args, text) = " " ++ col 16 12 (showSep " " cmds) (show args) text

  export
  displayErrors : {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         {auto s : Ref Syn SyntaxInfo} ->
         {auto m : Ref MD Metadata} ->
         {auto o : Ref ROpts REPLOpts} -> REPLResult -> Core ()
  displayErrors (ErrorLoadingFile x err) = printError (reflow "File error in" <++> pretty x <+> colon <++> pretty (show err))
  displayErrors _ = pure ()
