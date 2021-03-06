(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2017     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

open Pp
open Util
open Names
open Nameops
open Libnames
open Constrexpr
open Misctypes
open Decl_kinds

(***********************)
(* For binders parsing *)

let binding_kind_eq bk1 bk2 = match bk1, bk2 with
| Explicit, Explicit -> true
| Implicit, Implicit -> true
| _ -> false

let abstraction_kind_eq ak1 ak2 = match ak1, ak2 with
| AbsLambda, AbsLambda -> true
| AbsPi, AbsPi -> true
| _ -> false

let binder_kind_eq b1 b2 = match b1, b2 with
| Default bk1, Default bk2 -> binding_kind_eq bk1 bk2
| Generalized (bk1, ck1, b1), Generalized (bk2, ck2, b2) ->
  binding_kind_eq bk1 bk2 && binding_kind_eq ck1 ck2 &&
  (if b1 then b2 else not b2)
| _ -> false

let default_binder_kind = Default Explicit

let names_of_local_assums bl =
  List.flatten (List.map (function CLocalAssum(l,_,_)->l|_->[]) bl)

let names_of_local_binders bl =
  List.flatten (List.map (function CLocalAssum(l,_,_)->l|CLocalDef(l,_,_)->[l]|CLocalPattern _ -> assert false) bl)

(**********************************************************************)
(* Functions on constr_expr *)

(* Note: redundant Numeral representations such as -0 and +0 (or different
   numbers of leading zeros) are considered different here. *)

let prim_token_eq t1 t2 = match t1, t2 with
| Numeral (n1,s1), Numeral (n2,s2) -> String.equal n1 n2 && s1 == s2
| String s1, String s2 -> String.equal s1 s2
| _ -> false

let explicitation_eq ex1 ex2 = match ex1, ex2 with
| ExplByPos (i1, id1), ExplByPos (i2, id2) ->
  Int.equal i1 i2 && Option.equal Id.equal id1 id2
| ExplByName id1, ExplByName id2 ->
  Id.equal id1 id2
| _ -> false

let eq_located f (_, x) (_, y) = f x y

let rec cases_pattern_expr_eq p1 p2 =
  if CAst.(p1.v == p2.v) then true
  else match CAst.(p1.v, p2.v) with
  | CPatAlias(a1,i1), CPatAlias(a2,i2) ->
      Id.equal i1 i2 && cases_pattern_expr_eq a1 a2
  | CPatCstr(c1,a1,b1), CPatCstr(c2,a2,b2) ->
      eq_reference c1 c2 &&
      Option.equal (List.equal cases_pattern_expr_eq) a1 a2 &&
      List.equal cases_pattern_expr_eq b1 b2
  | CPatAtom(r1), CPatAtom(r2) ->
    Option.equal eq_reference r1 r2
  | CPatOr a1, CPatOr a2 ->
    List.equal cases_pattern_expr_eq a1 a2
  | CPatNotation (n1, s1, l1), CPatNotation (n2, s2, l2) ->
    String.equal n1 n2 &&
    cases_pattern_notation_substitution_eq s1 s2 &&
    List.equal cases_pattern_expr_eq l1 l2
  | CPatPrim i1, CPatPrim i2 ->
    prim_token_eq i1 i2
  | CPatRecord l1, CPatRecord l2 ->
    let equal (r1, e1) (r2, e2) =
      eq_reference r1 r2 && cases_pattern_expr_eq e1 e2
    in
    List.equal equal l1 l2
  | CPatDelimiters(s1,e1), CPatDelimiters(s2,e2) ->
    String.equal s1 s2 && cases_pattern_expr_eq e1 e2
  | _ -> false

and cases_pattern_notation_substitution_eq (s1, n1) (s2, n2) =
  List.equal cases_pattern_expr_eq s1 s2 &&
  List.equal (List.equal cases_pattern_expr_eq) n1 n2

let eq_universes u1 u2 =
  match u1, u2 with
  | None, None -> true
  | Some l, Some l' -> l = l'
  | _, _ -> false

let rec constr_expr_eq e1 e2 =
  if CAst.(e1.v == e2.v) then true
  else match CAst.(e1.v, e2.v) with
    | CRef (r1,u1), CRef (r2,u2) -> eq_reference r1 r2 && eq_universes u1 u2
    | CFix(id1,fl1), CFix(id2,fl2) ->
      eq_located Id.equal id1 id2 &&
      List.equal fix_expr_eq fl1 fl2
    | CCoFix(id1,fl1), CCoFix(id2,fl2) ->
      eq_located Id.equal id1 id2 &&
      List.equal cofix_expr_eq fl1 fl2
    | CProdN(bl1,a1), CProdN(bl2,a2) ->
      List.equal binder_expr_eq bl1 bl2 &&
      constr_expr_eq a1 a2
    | CLambdaN(bl1,a1), CLambdaN(bl2,a2) ->
      List.equal binder_expr_eq bl1 bl2 &&
      constr_expr_eq a1 a2
    | CLetIn((_,na1),a1,t1,b1), CLetIn((_,na2),a2,t2,b2) ->
      Name.equal na1 na2 &&
      constr_expr_eq a1 a2 &&
      Option.equal constr_expr_eq t1 t2 &&
      constr_expr_eq b1 b2
    | CAppExpl((proj1,r1,_),al1), CAppExpl((proj2,r2,_),al2) ->
      Option.equal Int.equal proj1 proj2 &&
      eq_reference r1 r2 &&
      List.equal constr_expr_eq al1 al2
    | CApp((proj1,e1),al1), CApp((proj2,e2),al2) ->
      Option.equal Int.equal proj1 proj2 &&
      constr_expr_eq e1 e2 &&
      List.equal args_eq al1 al2
    | CRecord l1, CRecord l2 ->
      let field_eq (r1, e1) (r2, e2) =
        eq_reference r1 r2 && constr_expr_eq e1 e2
      in
      List.equal field_eq l1 l2
    | CCases(_,r1,a1,brl1), CCases(_,r2,a2,brl2) ->
      (** Don't care about the case_style *)
      Option.equal constr_expr_eq r1 r2 &&
      List.equal case_expr_eq a1 a2 &&
      List.equal branch_expr_eq brl1 brl2
    | CLetTuple (n1, (m1, e1), t1, b1), CLetTuple (n2, (m2, e2), t2, b2) ->
      List.equal (eq_located Name.equal) n1 n2 &&
      Option.equal (eq_located Name.equal) m1 m2 &&
      Option.equal constr_expr_eq e1 e2 &&
      constr_expr_eq t1 t2 &&
      constr_expr_eq b1 b2
    | CIf (e1, (n1, r1), t1, f1), CIf (e2, (n2, r2), t2, f2) ->
      constr_expr_eq e1 e2 &&
      Option.equal (eq_located Name.equal) n1 n2 &&
      Option.equal constr_expr_eq r1 r2 &&
      constr_expr_eq t1 t2 &&
      constr_expr_eq f1 f2
    | CHole _, CHole _ -> true
    | CPatVar i1, CPatVar i2 ->
      Id.equal i1 i2
    | CEvar (id1, c1), CEvar (id2, c2) ->
      Id.equal id1 id2 && List.equal instance_eq c1 c2
    | CSort s1, CSort s2 ->
      Miscops.glob_sort_eq s1 s2
  | CCast(t1,c1), CCast(t2,c2) ->
    constr_expr_eq t1 t2 && cast_expr_eq c1 c2
    | CNotation(n1, s1), CNotation(n2, s2) ->
      String.equal n1 n2 &&
      constr_notation_substitution_eq s1 s2
    | CPrim i1, CPrim i2 ->
      prim_token_eq i1 i2
    | CGeneralization (bk1, ak1, e1), CGeneralization (bk2, ak2, e2) ->
      binding_kind_eq bk1 bk2 &&
      Option.equal abstraction_kind_eq ak1 ak2 &&
      constr_expr_eq e1 e2
    | CDelimiters(s1,e1), CDelimiters(s2,e2) ->
      String.equal s1 s2 &&
      constr_expr_eq e1 e2
    | CProj(p1,c1), CProj(p2,c2) ->
      eq_reference p1 p2 && constr_expr_eq c1 c2
  | (CRef _ | CFix _ | CCoFix _ | CProdN _ | CLambdaN _ | CLetIn _ | CAppExpl _
     | CApp _ | CRecord _ | CCases _ | CLetTuple _ | CIf _ | CHole _
     | CPatVar _ | CEvar _ | CSort _ | CCast _ | CNotation _ | CPrim _
     | CGeneralization _ | CDelimiters _ | CProj _), _ -> false

and args_eq (a1,e1) (a2,e2) =
  Option.equal (eq_located explicitation_eq) e1 e2 &&
  constr_expr_eq a1 a2

and case_expr_eq (e1, n1, p1) (e2, n2, p2) =
  constr_expr_eq e1 e2 &&
  Option.equal (eq_located Name.equal) n1 n2 &&
  Option.equal cases_pattern_expr_eq p1 p2

and branch_expr_eq (_, (p1, e1)) (_, (p2, e2)) =
  List.equal (List.equal cases_pattern_expr_eq) p1 p2 &&
  constr_expr_eq e1 e2

and binder_expr_eq ((n1, _, e1) : binder_expr) (n2, _, e2) =
  (** Don't care about the [binder_kind] *)
  List.equal (eq_located Name.equal) n1 n2 && constr_expr_eq e1 e2

and fix_expr_eq (id1,(j1, r1),bl1,a1,b1) (id2,(j2, r2),bl2,a2,b2) =
  (eq_located Id.equal id1 id2) &&
  Option.equal (eq_located Id.equal) j1 j2 &&
  recursion_order_expr_eq r1 r2 &&
  List.equal local_binder_eq bl1 bl2 &&
  constr_expr_eq a1 a2 &&
  constr_expr_eq b1 b2

and cofix_expr_eq (id1,bl1,a1,b1) (id2,bl2,a2,b2) =
  (eq_located Id.equal id1 id2) &&
  List.equal local_binder_eq bl1 bl2 &&
  constr_expr_eq a1 a2 &&
  constr_expr_eq b1 b2

and recursion_order_expr_eq r1 r2 = match r1, r2 with
  | CStructRec, CStructRec -> true
  | CWfRec e1, CWfRec e2 -> constr_expr_eq e1 e2
  | CMeasureRec (e1, o1), CMeasureRec (e2, o2) ->
    constr_expr_eq e1 e2 && Option.equal constr_expr_eq o1 o2
  | _ -> false

and local_binder_eq l1 l2 = match l1, l2 with
  | CLocalDef (n1, e1, t1), CLocalDef (n2, e2, t2) ->
    eq_located Name.equal n1 n2 && constr_expr_eq e1 e2 && Option.equal constr_expr_eq t1 t2
  | CLocalAssum (n1, _, e1), CLocalAssum (n2, _, e2) ->
    (** Don't care about the [binder_kind] *)
    List.equal (eq_located Name.equal) n1 n2 && constr_expr_eq e1 e2
  | _ -> false

and constr_notation_substitution_eq (e1, el1, bl1) (e2, el2, bl2) =
  List.equal constr_expr_eq e1 e2 &&
  List.equal (List.equal constr_expr_eq) el1 el2 &&
  List.equal (List.equal local_binder_eq) bl1 bl2

and instance_eq (x1,c1) (x2,c2) =
  Id.equal x1 x2 && constr_expr_eq c1 c2

and cast_expr_eq c1 c2 = match c1, c2 with
| CastConv t1, CastConv t2
| CastVM t1, CastVM t2
| CastNative t1, CastNative t2 -> constr_expr_eq t1 t2
| CastCoerce, CastCoerce -> true
| CastConv _, _
| CastVM _, _
| CastNative _, _
| CastCoerce, _ -> false

let constr_loc c = CAst.(c.loc)
let cases_pattern_expr_loc cp = CAst.(cp.loc)

let local_binder_loc = function
  | CLocalAssum ((loc,_)::_,_,t)
  | CLocalDef ((loc,_),t,None) -> Loc.merge_opt loc (constr_loc t)
  | CLocalDef ((loc,_),b,Some t) -> Loc.merge_opt loc (Loc.merge_opt (constr_loc b) (constr_loc t))
  | CLocalAssum ([],_,_) -> assert false
  | CLocalPattern (loc,_) -> loc

let local_binders_loc bll = match bll with
  | []     -> None
  | h :: l -> Loc.merge_opt (local_binder_loc h) (local_binder_loc (List.last bll))

(** Folds and maps *)

(* Legacy functions *)
let down_located f (_l, x) = f x

let is_constructor id =
  try Globnames.isConstructRef
        (Smartlocate.global_of_extended_global
           (Nametab.locate_extended (qualid_of_ident id)))
  with Not_found -> false

let rec cases_pattern_fold_names f a pt = match CAst.(pt.v) with
  | CPatRecord l ->
    List.fold_left (fun acc (r, cp) -> cases_pattern_fold_names f acc cp) a l
  | CPatAlias (pat,id) -> f id a
  | CPatOr (patl) ->
    List.fold_left (cases_pattern_fold_names f) a patl
  | CPatCstr (_,patl1,patl2) ->
    List.fold_left (cases_pattern_fold_names f)
      (Option.fold_left (List.fold_left (cases_pattern_fold_names f)) a patl1) patl2
  | CPatNotation (_,(patl,patll),patl') ->
    List.fold_left (cases_pattern_fold_names f)
      (List.fold_left (cases_pattern_fold_names f) a (patl@List.flatten patll)) patl'
  | CPatDelimiters (_,pat) -> cases_pattern_fold_names f a pat
  | CPatAtom (Some (Ident (_,id))) when not (is_constructor id) -> f id a
  | CPatPrim _ | CPatAtom _ -> a
  | CPatCast ({CAst.loc},_) ->
    CErrors.user_err ?loc ~hdr:"cases_pattern_fold_names"
      (Pp.strbrk "Casts are not supported here.")

let ids_of_pattern =
  cases_pattern_fold_names Id.Set.add Id.Set.empty

let ids_of_pattern_list =
  List.fold_left
    (List.fold_left (cases_pattern_fold_names Id.Set.add))
    Id.Set.empty

let ids_of_cases_indtype p =
  cases_pattern_fold_names Id.Set.add Id.Set.empty p

let ids_of_cases_tomatch tms =
  List.fold_right
    (fun (_, ona, indnal) l ->
       Option.fold_right (fun t ids -> cases_pattern_fold_names Id.Set.add ids t)
         indnal
         (Option.fold_right (down_located (Name.fold_right Id.Set.add)) ona l))
    tms Id.Set.empty

let rec fold_constr_expr_binders g f n acc b = function
  | (nal,bk,t)::l ->
    let nal = snd (List.split nal) in
    let n' = List.fold_right (Name.fold_right g) nal n in
    f n (fold_constr_expr_binders g f n' acc b l) t
  | [] ->
    f n acc b

let rec fold_local_binders g f n acc b = function
  | CLocalAssum (nal,bk,t)::l ->
    let nal = snd (List.split nal) in
    let n' = List.fold_right (Name.fold_right g) nal n in
    f n (fold_local_binders g f n' acc b l) t
  | CLocalDef ((_,na),c,t)::l ->
    Option.fold_left (f n) (f n (fold_local_binders g f (Name.fold_right g na n) acc b l) c) t
  | CLocalPattern (_,(pat,t))::l ->
    let acc = fold_local_binders g f (cases_pattern_fold_names g n pat) acc b l in
    Option.fold_left (f n) acc t
  | [] ->
    f n acc b

let fold_constr_expr_with_binders g f n acc = CAst.with_val (function
    | CAppExpl ((_,_,_),l) -> List.fold_left (f n) acc l
    | CApp ((_,t),l) -> List.fold_left (f n) (f n acc t) (List.map fst l)
    | CProdN (l,b) | CLambdaN (l,b) -> fold_constr_expr_binders g f n acc b l
    | CLetIn (na,a,t,b) ->
      f (Name.fold_right g (snd na) n) (Option.fold_left (f n) (f n acc a) t) b
    | CCast (a,(CastConv b|CastVM b|CastNative b)) -> f n (f n acc a) b
    | CCast (a,CastCoerce) -> f n acc a
    | CNotation (_,(l,ll,bll)) ->
      (* The following is an approximation: we don't know exactly if
         an ident is binding nor to which subterms bindings apply *)
      let acc = List.fold_left (f n) acc (l@List.flatten ll) in
      List.fold_left (fun acc bl -> fold_local_binders g f n acc (CAst.make @@ CHole (None,IntroAnonymous,None)) bl) acc bll
    | CGeneralization (_,_,c) -> f n acc c
    | CDelimiters (_,a) -> f n acc a
    | CHole _ | CEvar _ | CPatVar _ | CSort _ | CPrim _ | CRef _ ->
      acc
    | CRecord l -> List.fold_left (fun acc (id, c) -> f n acc c) acc l
    | CCases (sty,rtnpo,al,bl) ->
      let ids = ids_of_cases_tomatch al in
      let acc = Option.fold_left (f (Id.Set.fold g ids n)) acc rtnpo in
      let acc = List.fold_left (f n) acc (List.map (fun (fst,_,_) -> fst) al) in
      List.fold_right (fun (loc,(patl,rhs)) acc ->
          let ids = ids_of_pattern_list patl in
          f (Id.Set.fold g ids n) acc rhs) bl acc
    | CLetTuple (nal,(ona,po),b,c) ->
      let n' = List.fold_right (down_located (Name.fold_right g)) nal n in
      f (Option.fold_right (down_located (Name.fold_right g)) ona n') (f n acc b) c
    | CIf (c,(ona,po),b1,b2) ->
      let acc = f n (f n (f n acc b1) b2) c in
      Option.fold_left
        (f (Option.fold_right (down_located (Name.fold_right g)) ona n)) acc po
    | CFix (_,l) ->
      let n' = List.fold_right (fun ((_,id),_,_,_,_) -> g id) l n in
      List.fold_right (fun (_,(_,o),lb,t,c) acc ->
          fold_local_binders g f n'
            (fold_local_binders g f n acc t lb) c lb) l acc
    | CCoFix (_,_) ->
      Feedback.msg_warning (strbrk "Capture check in multiple binders not done"); acc
    | CProj (_,c) ->
        f n acc c
  )

let free_vars_of_constr_expr c =
  let rec aux bdvars l = function
    | { CAst.v = CRef (Ident (_,id),_) } -> if Id.List.mem id bdvars then l else Id.Set.add id l
    | c -> fold_constr_expr_with_binders (fun a l -> a::l) aux bdvars l c
  in aux [] Id.Set.empty c

let occur_var_constr_expr id c = Id.Set.mem id (free_vars_of_constr_expr c)

(* Used in correctness and interface *)
let map_binder g e nal = List.fold_right (down_located (Name.fold_right g)) nal e

let map_binders f g e bl =
  (* TODO: avoid variable capture in [t] by some [na] in [List.tl nal] *)
  let h (e,bl) (nal,bk,t) = (map_binder g e nal,(nal,bk,f e t)::bl) in
  let (e,rbl) = List.fold_left h (e,[]) bl in
  (e, List.rev rbl)

let map_local_binders f g e bl =
  (* TODO: avoid variable capture in [t] by some [na] in [List.tl nal] *)
  let h (e,bl) = function
      CLocalAssum(nal,k,ty) ->
      (map_binder g e nal, CLocalAssum(nal,k,f e ty)::bl)
    | CLocalDef((loc,na),c,ty) ->
      (Name.fold_right g na e, CLocalDef((loc,na),f e c,Option.map (f e) ty)::bl)
    | CLocalPattern (loc,(pat,t)) ->
      let ids = ids_of_pattern pat in
      (Id.Set.fold g ids e, CLocalPattern (loc,(pat,Option.map (f e) t))::bl) in
  let (e,rbl) = List.fold_left h (e,[]) bl in
  (e, List.rev rbl)

let map_constr_expr_with_binders g f e = CAst.map (function
    | CAppExpl (r,l) -> CAppExpl (r,List.map (f e) l)
    | CApp ((p,a),l) ->
      CApp ((p,f e a),List.map (fun (a,i) -> (f e a,i)) l)
    | CProdN (bl,b) ->
      let (e,bl) = map_binders f g e bl in CProdN (bl,f e b)
    | CLambdaN (bl,b) ->
      let (e,bl) = map_binders f g e bl in CLambdaN (bl,f e b)
    | CLetIn (na,a,t,b) ->
      CLetIn (na,f e a,Option.map (f e) t,f (Name.fold_right g (snd na) e) b)
    | CCast (a,c) -> CCast (f e a, Miscops.map_cast_type (f e) c)
    | CNotation (n,(l,ll,bll)) ->
      (* This is an approximation because we don't know what binds what *)
      CNotation (n,(List.map (f e) l,List.map (List.map (f e)) ll,
                    List.map (fun bl -> snd (map_local_binders f g e bl)) bll))
    | CGeneralization (b,a,c) -> CGeneralization (b,a,f e c)
    | CDelimiters (s,a) -> CDelimiters (s,f e a)
    | CHole _ | CEvar _ | CPatVar _ | CSort _
    | CPrim _ | CRef _ as x -> x
    | CRecord l -> CRecord (List.map (fun (id, c) -> (id, f e c)) l)
    | CCases (sty,rtnpo,a,bl) ->
      let bl = List.map (fun (loc,(patl,rhs)) ->
          let ids = ids_of_pattern_list patl in
          (loc,(patl,f (Id.Set.fold g ids e) rhs))) bl in
      let ids = ids_of_cases_tomatch a in
      let po = Option.map (f (Id.Set.fold g ids e)) rtnpo in
      CCases (sty, po, List.map (fun (tm,x,y) -> f e tm,x,y) a,bl)
    | CLetTuple (nal,(ona,po),b,c) ->
      let e' = List.fold_right (down_located (Name.fold_right g)) nal e in
      let e'' = Option.fold_right (down_located (Name.fold_right g)) ona e in
      CLetTuple (nal,(ona,Option.map (f e'') po),f e b,f e' c)
    | CIf (c,(ona,po),b1,b2) ->
      let e' = Option.fold_right (down_located (Name.fold_right g)) ona e in
      CIf (f e c,(ona,Option.map (f e') po),f e b1,f e b2)
    | CFix (id,dl) ->
      CFix (id,List.map (fun (id,n,bl,t,d) ->
          let (e',bl') = map_local_binders f g e bl in
          let t' = f e' t in
          (* Note: fix names should be inserted before the arguments... *)
          let e'' = List.fold_left (fun e ((_,id),_,_,_,_) -> g id e) e' dl in
          let d' = f e'' d in
          (id,n,bl',t',d')) dl)
    | CCoFix (id,dl) ->
      CCoFix (id,List.map (fun (id,bl,t,d) ->
          let (e',bl') = map_local_binders f g e bl in
          let t' = f e' t in
          let e'' = List.fold_left (fun e ((_,id),_,_,_) -> g id e) e' dl in
          let d' = f e'' d in
          (id,bl',t',d')) dl)
    | CProj (p,c) ->
      CProj (p, f e c)
  )

(* Used in constrintern *)
let rec replace_vars_constr_expr l = function
  | { CAst.loc; v = CRef (Ident (loc_id,id),us) } as x ->
    (try CAst.make ?loc @@ CRef (Ident (loc_id,Id.Map.find id l),us) with Not_found -> x)
  | c -> map_constr_expr_with_binders Id.Map.remove
           replace_vars_constr_expr l c

(* Returns the ranges of locs of the notation that are not occupied by args  *)
(* and which are then occupied by proper symbols of the notation (or spaces) *)

let locs_of_notation ?loc locs ntn =
  let unloc loc = Option.cata Loc.unloc (0,0) loc in
  let (bl, el) = unloc loc        in
  let locs =  List.map unloc locs in
  let rec aux pos = function
    | [] -> if Int.equal pos el then [] else [(pos,el)]
    | (ba,ea)::l -> if Int.equal pos ba then aux ea l else (pos,ba)::aux ea l
  in aux bl (List.sort (fun l1 l2 -> fst l1 - fst l2) locs)

let ntn_loc ?loc (args,argslist,binderslist) =
  locs_of_notation ?loc
    (List.map constr_loc (args@List.flatten argslist)@
     List.map local_binders_loc binderslist)

let patntn_loc ?loc (args,argslist) =
  locs_of_notation ?loc
    (List.map cases_pattern_expr_loc (args@List.flatten argslist))

let error_invalid_pattern_notation ?loc () =
  CErrors.user_err ?loc  (str "Invalid notation for pattern.")

(* Interpret the index of a recursion order annotation *)
let split_at_annot bl na =
  let names = List.map snd (names_of_local_assums bl) in
  match na with
  | None ->
    begin match names with
      | [] -> CErrors.user_err (Pp.str "A fixpoint needs at least one parameter.")
      | _ -> ([], bl)
    end
  | Some (loc, id) ->
    let rec aux acc = function
      | CLocalAssum (bls, k, t) as x :: rest ->
        let test (_, na) = match na with
          | Name id' -> Id.equal id id'
          | Anonymous -> false
        in
        let l, r = List.split_when test bls in
        begin match r with
          | [] -> aux (x :: acc) rest
          | _ ->
            let ans = match l with
              | [] -> acc
              | _ -> CLocalAssum (l, k, t) :: acc
            in
            (List.rev ans, CLocalAssum (r, k, t) :: rest)
        end
      | CLocalDef ((_,na),_,_) as x :: rest ->
        if Name.equal (Name id) na then
          CErrors.user_err ?loc
            (Id.print id ++ str" must be a proper parameter and not a local definition.")
        else
          aux (x :: acc) rest
      | CLocalPattern (_,_) :: rest ->
        Loc.raise ?loc (Stream.Error "pattern with quote not allowed after fix")
      | [] ->
        CErrors.user_err ?loc
          (str "No parameter named " ++ Id.print id ++ str".")
    in aux [] bl

(** Pseudo-constructors *)

let mkIdentC id   = CAst.make @@ CRef (Ident (Loc.tag id),None)
let mkRefC r      = CAst.make @@ CRef (r,None)
let mkCastC (a,k) = CAst.make @@ CCast (a,k)
let mkLambdaC (idl,bk,a,b) = CAst.make @@ CLambdaN ([idl,bk,a],b)
let mkLetInC  (id,a,t,b)   = CAst.make @@ CLetIn (id,a,t,b)
let mkProdC   (idl,bk,a,b) = CAst.make @@ CProdN ([idl,bk,a],b)

let mkAppC (f,l) =
  let l = List.map (fun x -> (x,None)) l in
  match CAst.(f.v) with
  | CApp (g,l') -> CAst.make @@ CApp (g, l' @ l)
  | _           -> CAst.make @@ CApp ((None, f), l)

let add_name_in_env env n =
  match snd n with
  | Anonymous -> env
  | Name id -> id :: env

let fresh_var env c =
  Namegen.next_ident_away (Id.of_string "pat")
    (List.fold_left (fun accu id -> Id.Set.add id accu) (free_vars_of_constr_expr c) env)

let expand_binders ?loc mkC bl c =
  let rec loop ?loc bl c =
    match bl with
    | [] -> ([], c)
    | b :: bl ->
      match b with
      | CLocalDef ((loc1,_) as n, oty, b) ->
        let env, c = loop ?loc:(Loc.merge_opt loc1 loc) bl c in
        let env = add_name_in_env env n in
        (env, CAst.make ?loc @@ CLetIn (n,oty,b,c))
      | CLocalAssum ((loc1,_)::_ as nl, bk, t) ->
        let env, c = loop ?loc:(Loc.merge_opt loc1 loc) bl c in
        let env = List.fold_left add_name_in_env env nl in
        (env, mkC ?loc (nl,bk,t) c)
      | CLocalAssum ([],_,_) -> loop ?loc bl c
      | CLocalPattern (loc1, (p, ty)) ->
        let env, c = loop ?loc:(Loc.merge_opt loc1 loc) bl c in
        let ni = fresh_var env c in
        let id = (loc1, Name ni) in
        let ty = match ty with
          | Some ty -> ty
          | None -> CAst.make ?loc:loc1 @@ CHole (None, IntroAnonymous, None)
        in
        let e = CAst.make @@ CRef (Libnames.Ident (loc1, ni), None) in
        let c = CAst.make ?loc @@
          CCases
            (LetPatternStyle, None, [(e,None,None)],
             [(Loc.tag ?loc:loc1 ([[p]], c))])
        in
        (ni :: env, mkC ?loc ([id],Default Explicit,ty) c)
  in
  let (_, c) = loop ?loc bl c in
  c

let mkCProdN ?loc bll c =
  let mk ?loc b c = CAst.make ?loc @@ CProdN ([b],c) in
  expand_binders ?loc mk bll c

let mkCLambdaN ?loc bll c =
  let mk ?loc b c = CAst.make ?loc @@ CLambdaN ([b],c) in
  expand_binders ?loc mk bll c

let coerce_reference_to_id = function
  | Ident (_,id) -> id
  | Qualid (loc,_) ->
    CErrors.user_err ?loc ~hdr:"coerce_reference_to_id"
      (str "This expression should be a simple identifier.")

let coerce_to_id = function
  | { CAst.v = CRef (Ident (loc,id),None) } -> (loc,id)
  | { CAst.loc; _ } -> CErrors.user_err ?loc
                         ~hdr:"coerce_to_id"
                         (str "This expression should be a simple identifier.")

let coerce_to_name = function
  | { CAst.v = CRef (Ident (loc,id),None) } -> (loc,Name id)
  | { CAst.loc; CAst.v = CHole (None,Misctypes.IntroAnonymous,None) } -> (loc,Anonymous)
  | { CAst.loc; _ } -> CErrors.user_err ?loc ~hdr:"coerce_to_name"
                         (str "This expression should be a name.")

let asymmetric_patterns = ref (false)
let _ = Goptions.declare_bool_option {
  Goptions.optdepr = false;
  Goptions.optname = "no parameters in constructors";
  Goptions.optkey = ["Asymmetric";"Patterns"];
  Goptions.optread = (fun () -> !asymmetric_patterns);
  Goptions.optwrite = (fun a -> asymmetric_patterns:=a);
}

(************************************************************************)
(* Deprecated *)
let abstract_constr_expr c bl = mkCLambdaN ?loc:(local_binders_loc bl) bl c
let prod_constr_expr c bl =  mkCProdN ?loc:(local_binders_loc bl) bl c
