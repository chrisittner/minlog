;; $Id: ets.scm 2691 2014-01-24 09:19:47Z schwicht $
;; 16. Extracted terms
;; ===================

(define (make-arrow-et type1 type2)
  (if (nulltype? type1)
      type2
      (if (nulltype? type2)
          (make-tconst "nulltype")
          (make-arrow type1 type2))))

(define (mk-arrow-et x . rest)
  (if (null? rest)
      x
      (make-arrow-et x (apply mk-arrow-et rest))))

(define (make-star-et type1 type2)
  (if (nulltype? type1)
      type2
      (if (nulltype? type2)
          type1
          (make-star type1 type2))))

;; When we want to execute the program, we have to replace cL by the
;; extracted program of its proof, and cGA by an assumed extracted term
;; to be provided by the user.  This can be achieved by adding
;; computation rules for cL and cGA.  We can be rather flexible here and
;; enable/block rewriting by using animate/deanimate as desired.

;; Notice that the type of the extracted term provided for a cGA must be
;; the et-type of the assumed formula.  When predicate variables are
;; present, one must use the type variables assigned to them in
;; PVAR-TO-TVAR-ALIST.

(define (animate thm-or-ga-name . opt-eterm)
  (let* ((pconst-name
	  (theorem-or-global-assumption-name-to-pconst-name thm-or-ga-name))
	 (pconst (pconst-name-to-pconst pconst-name))
	 (info1 (assoc thm-or-ga-name THEOREMS)))
    (if
     info1
     (let* ((proof (theorem-name-to-proof thm-or-ga-name))
	    (eterm (proof-to-extracted-term proof))
	    (neterm (nt eterm)))
       (add-computation-rule (make-term-in-const-form pconst) neterm))
     (let ((info2 (assoc thm-or-ga-name GLOBAL-ASSUMPTIONS)))
       (if
	info2
	(let* ((eterm (if (pair? opt-eterm)
			  (car opt-eterm)
			  (myerror "animate" "eterm expected for"
				   thm-or-ga-name)))
	       (et-type (formula-to-et-type
			 (aconst-to-uninst-formula
			  (global-assumption-name-to-aconst
			   thm-or-ga-name)))))
	  (if (not (equal? (term-to-type eterm) et-type))
	      (myerror "animate" "equal types expected"
		       (term-to-type eterm)
		       et-type))
	  (add-computation-rule (make-term-in-const-form pconst) eterm)))))))

(define (deanimate thm-or-ga-name)
  (let* ((pconst-name
	  (theorem-or-global-assumption-name-to-pconst-name thm-or-ga-name))
	 (pconst (pconst-name-to-pconst pconst-name))
	 (term (make-term-in-const-form pconst)))
    (remove-computation-rules-for term)))

;; formula-to-et-type and idpredconst-to-et-type are defined
;; simultaneously.  This makes sense, since the clauses and also the
;; cterms of an idpredconst are prior to the idpredconst.

(define (formula-to-et-type formula)
  (case (tag formula)
    ((atom) (make-tconst "nulltype"))
    ((predicate)
     (let ((pred (predicate-form-to-predicate formula)))
       (cond ((pvar-form? pred)
	      (if (pvar-with-positive-content? pred)
		  (PVAR-TO-TVAR pred)
		  (make-tconst "nulltype")))
	     ((predconst-form? pred)
	      (if (string=? "Total" (predconst-to-name pred))
		  (car (arity-to-types (predconst-to-arity pred)))
		  (make-tconst "nulltype")))
	     ((idpredconst-form? pred) (idpredconst-to-et-type pred))
	     (else (myerror
		    "formula-to-et-type" "predicate expected" pred)))))
    ((imp)
     (make-arrow-et
      (formula-to-et-type (imp-form-to-premise formula))
      (formula-to-et-type (imp-form-to-conclusion formula))))
    ((impnc)
     (formula-to-et-type (impnc-form-to-conclusion formula)))
    ((and)
     (make-star-et
      (formula-to-et-type (and-form-to-left formula))
      (formula-to-et-type (and-form-to-right formula))))
    ((all)
     (make-arrow-et
      (var-to-type (all-form-to-var formula))
      (formula-to-et-type (all-form-to-kernel formula))))
    ((ex) (make-star-et
	   (var-to-type (ex-form-to-var formula))
	   (formula-to-et-type (ex-form-to-kernel formula))))
    ((allnc)
     (formula-to-et-type (allnc-form-to-kernel formula)))
    ((exca excl excu)
     (formula-to-et-type (unfold-formula formula)))
    (else (myerror "formula-to-et-type" "formula expected" formula))))

(define (idpredconst-to-et-type idpc)
  (let* ((name (idpredconst-to-name idpc))
	 (opt-alg-name (idpredconst-name-to-opt-alg-name name)))
    (if
     (null? opt-alg-name)
     (make-tconst "nulltype")
     (let* ((string (car opt-alg-name))
	    (types (idpredconst-to-types idpc))
	    (cterms (idpredconst-to-cterms idpc))
	    (tvars (idpredconst-name-to-tvars name))
	    (idpc-pvars (idpredconst-name-to-pvars name))
	    (param-pvars (idpredconst-name-to-param-pvars name))
	    (names (idpredconst-name-to-simidpc-names name))
	    (clauses-with-names
	     (apply append (map idpredconst-name-to-clauses-with-names names)))
	    (clauses (map car clauses-with-names))
	    (et-types (map formula-to-et-type clauses))
	    (idpc-tvars (map PVAR-TO-TVAR idpc-pvars))
	    (et-tvars (set-minus (apply union (map type-to-tvars et-types))
				 idpc-tvars))
	    (relevant-types (do ((l1 tvars (cdr l1))
				 (l2 types (cdr l2))
				 (res '() (let ((tvar (car l1))
						(type (car l2)))
					    (if (member tvar et-tvars)
						(cons type res)
						res))))
				((null? l2) (reverse res))))
	    (relevant-cterm-types
	     (do ((l1 param-pvars (cdr l1))
		  (l2 cterms (cdr l2))
		  (res '() (let* ((pvar (car l1))
				  (cterm (car l2))
				  (formula (cterm-to-formula cterm))
				  (cterm-et-type
				   (formula-to-et-type formula)))
			     (if (and (pvar-with-positive-content? pvar)
				      (member (PVAR-TO-TVAR pvar) et-tvars))
				 (cons cterm-et-type res)
				 res))))
		 ((null? l1) (reverse res))))
	    (relevant-types-and-cterm-types
	     (append relevant-types relevant-cterm-types))
	    (nc-indicator (append (make-list (length relevant-types) #f)
				  (map nulltype? relevant-cterm-types)))
	    (new-alg-name (alg-name-and-nc-indicator-to-alg-name
			   string nc-indicator)))
       (cond
	((string=? "nulltype" new-alg-name) (make-tconst "nulltype"))
	((string=? "identity" new-alg-name)
	 (car (list-transform-positive relevant-types-and-cterm-types
		(lambda (t) (not (nulltype? t))))))
	(else ;proper alg name
	 (apply make-alg
		new-alg-name
		(list-transform-positive relevant-types-and-cterm-types
		  (lambda (t) (not (nulltype? t)))))))))))

(define ALG-NAME-AND-NC-INDICATOR-TO-ALG-NAME '())

(set! ALG-NAME-AND-NC-INDICATOR-TO-ALG-NAME
      (append (list (list (list "identity" '(#t)) "nulltype")
		    (list (list "ysum" '(#t #f)) "uysum")
		    (list (list "ysum" '(#f #t)) "ysumu")
		    (list (list "ysum" '(#t #t)) "boole")
		    (list (list "yprod" '(#t #f)) "identity")
		    (list (list "yprod" '(#f #t)) "identity")
		    (list (list "yprod" '(#t #t)) "nulltype"))
	      ALG-NAME-AND-NC-INDICATOR-TO-ALG-NAME))

(define (alg-name-and-nc-indicator-to-alg-name alg-name nc-indicator)
  (let ((info1 (assoc (list alg-name nc-indicator)
		      ALG-NAME-AND-NC-INDICATOR-TO-ALG-NAME)))
    (cond
     (info1 (cadr info1))
     ((apply and-op (map not nc-indicator)) alg-name)
     (else ;check whether the default addition was done
      (let* ((default-alg-name
	       (apply string-append alg-name (map (lambda (p) (if p "nc" "cr"))
						  nc-indicator)))
	     (info2 (assoc default-alg-name ALGEBRAS)))
	(if
	 info2 default-alg-name ;else create new algebras
	 (let* ((tvars (alg-name-to-tvars alg-name))
		(tsubst
		 (do ((l1 tvars (cdr l1))
		      (l2 nc-indicator (cdr l2))
		      (res '()
			   (if (car l2)
			       (cons (list (car l1) (make-tconst "nulltype"))
				     res)
			       res)))
		     ((null? l1) (reverse res))))
		(simalg-names (alg-name-to-simalg-names alg-name))
		(typed-constr-names
		 (apply union (map alg-name-to-typed-constr-names
				   simalg-names)))
		(simalg-names-et
		 (map (lambda (name)
			(apply string-append
			       name (map (lambda (p) (if p "nc" "cr"))
					 nc-indicator)))
		      simalg-names))
		(constr-names
		 (map typed-constr-name-to-name typed-constr-names))
		(constr-names-et
		 (map (lambda (name)
			(apply string-append
			       name (map (lambda (p) (if p "Nc" "Cr"))
					 nc-indicator)))
		      constr-names))
		(constr-types
		 (map typed-constr-name-to-type typed-constr-names))
		(constr-types-with-nulltype
		 (map (lambda (type) (type-substitute type tsubst))
		      constr-types))
		(tvars-with-nulltype
		 (alg-form-to-types (arrow-form-to-final-val-type
				     (car constr-types-with-nulltype))))
		(simalgs-with-nulltype
		 (map (lambda (simalg-name)
			(apply make-alg simalg-name tvars-with-nulltype))
		      simalg-names))
		(simalg-strings (map type-to-string simalgs-with-nulltype))
		(shortened-constr-types-with-nulltype
		 (map remove-nulltype-argtypes constr-types-with-nulltype))
		(shortened-constr-type-strings-with-nulltype
		 (map type-to-string shortened-constr-types-with-nulltype))
		(constr-type-strings-et
		 (map (lambda (string)
			(string-replace-substrings
			 string simalg-strings simalg-names-et))
		      shortened-constr-type-strings-with-nulltype))
		(constr-type-strings-et-with-names
		 (map list constr-type-strings-et constr-names-et)))
	   (apply add-algs simalg-names-et constr-type-strings-et-with-names)
	   (apply string-append alg-name (map (lambda (p) (if p "nc" "cr"))
					      nc-indicator)))))))))

(define (formula-of-nulltype? formula)
  (case (tag formula)
    ((atom) #t)
    ((predicate)
     (let ((pred (predicate-form-to-predicate formula)))
       (cond
	((pvar-form? pred)
	 (not (pvar-with-positive-content? pred)))
	((predconst-form? pred)
	 (not (string=? (predconst-to-name pred) "Total")))
	((idpredconst-form? pred)
	 (let* ((name (idpredconst-to-name pred))
		(opt-alg-name (idpredconst-name-to-opt-alg-name name)))
	   (or (null? opt-alg-name)
	       (equal? (make-tconst "nulltype")
		       (idpredconst-to-et-type pred)))))
	(else (myerror "formula-of-nulltype?" "predicate expected" pred)))))
    ((imp) (formula-of-nulltype? (imp-form-to-conclusion formula)))
    ((impnc) (formula-of-nulltype? (impnc-form-to-conclusion formula)))
    ((and) (and (formula-of-nulltype? (and-form-to-left formula))
		(formula-of-nulltype? (and-form-to-right formula))))
    ((all) (formula-of-nulltype? (all-form-to-kernel formula)))
    ((ex) #f)
    ((allnc) (formula-of-nulltype? (allnc-form-to-kernel formula)))
    ((exca excl excu) (formula-of-nulltype? (unfold-formula formula)))
    (else (myerror "formula-of-nulltype?" "formula expected" formula))))

(define (formula-of-nulltype-under-extension? formula)
  (case (tag formula)
    ((atom) #t)
    ((predicate)
     (let ((pred (predicate-form-to-predicate formula)))
       (cond ((pvar-form? pred)
	      (not (pvar-with-positive-content? pred)))
	     ((predconst-form? pred)
	      (not (string=? (predconst-to-name pred) "Total")))
	     ((idpredconst-form? pred)
	      (let* ((name (idpredconst-to-name pred))
		     (opt-alg-name (idpredconst-name-to-opt-alg-name name)))
		(or (and (null? opt-alg-name)
			 (not (string=? name "EdD"))
			 (not (string=? name "ExU"))
			 (not (string=? name "ExUT"))
			 (not (string=? name "AndU")))
		    (and (not (null? opt-alg-name))
			 (string=? "identity" (car opt-alg-name))
			 (equal? (make-tconst "nulltype")
				 (idpredconst-to-et-type pred))))))
	     (else (myerror "formula-of-nulltype-under-extension?"
			    "predicate expected" pred)))))
    ((imp)
     (formula-of-nulltype-under-extension? (imp-form-to-conclusion formula)))
    ((impnc)
     (formula-of-nulltype-under-extension? (impnc-form-to-conclusion formula)))
    ((and)
     (and (formula-of-nulltype-under-extension? (and-form-to-left formula))
	  (formula-of-nulltype-under-extension? (and-form-to-right formula))))
    ((all) (formula-of-nulltype-under-extension? (all-form-to-kernel formula)))
    ((ex) #f)
    ((allnc)
     (formula-of-nulltype-under-extension? (allnc-form-to-kernel formula)))
    ((exca excl excu)
     (formula-of-nulltype-under-extension? (unfold-formula formula)))
    (else (myerror "formula-of-nulltype-under-extension?"
		   "formula expected" formula))))

;; Initial THEOREMS moved here because formula-substitute (used in
;; make-proof-in-aconst-form for AllncTotalIntro) needs
;; formula-of-nulltype?

;; Axioms AllTotalIntro (was AllPartial-All), AllTotalElim (was
;; All-AllPartial), AllncTotalIntro, AllncTotalElim are viewed as
;; initial theorems, with the same name.  This makes it easy to use
;; them in interactive proofs.  Further abbreviation axioms
;; AtomToEqDTrue EqDTrueToAtom ExTotalIntro (was ExPartial-Ex) and
;; ExTotalElim (was Ex-ExPartial) are added to THEOREMS .  From them
;; Truth := atom(True) (a preferred alternative to Truth-Axiom) is
;; proved and added to THEOREMS.  Then EqDCompat EqDCompatRev EqDSym
;; EqDTrans EqDCompatApp EFEqD are proven and added to THEOREMS

(set!
 THEOREMS
 (list
  (list "AllTotalIntro" alltotal-intro-aconst
	(make-proof-in-aconst-form alltotal-intro-aconst))
  (list "AllTotalElim" alltotal-elim-aconst
	(make-proof-in-aconst-form alltotal-elim-aconst))
  (list "AllncTotalIntro" allnctotal-intro-aconst
	(make-proof-in-aconst-form allnctotal-intro-aconst))
  (list "AllncTotalElim" allnctotal-elim-aconst
	(make-proof-in-aconst-form allnctotal-elim-aconst))
					;the following are obsolete
  ;; (list "AtomTrue" atom-true-aconst atom-true-proof)
  ;; (list "AtomFalse" atom-false-aconst atom-false-proof)
  ;; (list "EfqAtom" efq-atom-aconst efq-atom-proof)
  ;; (list "Truth-Axiom" truth-aconst (make-proof-in-aconst-form truth-aconst))
  (list "Truth-Axiom" (make-aconst "Truth-Axiom" 'axiom truth empty-subst)
	(make-proof-in-aconst-form
	 (make-aconst "Truth-Axiom" 'axiom truth empty-subst)))))

;; We add totality for the algebras introduced before.  This can be
;; done only here, because we need formula-of-nulltype?

(set! COMMENT-FLAG #f)
(add-totality "unit")
(add-totality "boole")
(add-totality "yprod")
(add-rtotality "yprod")
(add-totality "ysum")
(add-rtotality "ysum")
(add-totality "uysum")
(add-rtotality "uysum")
(add-totality "ysumu")
(add-rtotality "ysumu")
(set! COMMENT-FLAG #t)

;; We initially supply the following global assumptions.
;; This can be done only here, because for add-global-assumption we need
;; formula-to-et-type.
;; EfqLog: bot -> Pvar
;; StabLog: ((Pvar -> bot) -> bot) -> Pvar
;; Efq: F -> Pvar
;; Stab: ((Pvar -> F) -> F) -> Pvar

(add-global-assumption
 "EfqLog" (make-imp
	   falsity-log
	   (make-predicate-formula (mk-pvar (make-arity)))))

(add-global-assumption
 "StabLog"
 (let ((p (make-predicate-formula (mk-pvar (make-arity)))))
   (make-imp (make-imp (make-imp p falsity-log) falsity-log) p)))

(add-global-assumption
 "Efq" (make-imp
	(make-atomic-formula
	 (make-term-in-const-form (constr-name-to-constr "False")))
	(make-predicate-formula (mk-pvar (make-arity)))))

(add-global-assumption
 "Stab"
 (let ((f (make-atomic-formula
	   (make-term-in-const-form (constr-name-to-constr "False"))))
       (p (make-predicate-formula (mk-pvar (make-arity)))))
   (make-imp (make-imp (make-imp p f) f) p)))

(define (make-avar-to-var)
  ;; returns a procedure assigning to assumption variables whose types
  ;; have computational content new object vars of the corresponding
  ;; et-type.  Remembers the assignment done so far.
  (let ((avar-assoc-list '()))
    (lambda (avar)
      (let ((info (assoc-wrt avar=? avar avar-assoc-list)))
	(if info
	    (cadr info)
	    (let* ((formula (avar-to-formula avar))
		   (type (formula-to-et-type formula))
		   (new-var (if (nulltype? type)
				(myerror "make-avar-to-var"
					 "computational content expected in"
					 formula)
				(type-to-new-var type))))
	      (begin (set! avar-assoc-list
			   (cons (list avar new-var) avar-assoc-list))
		     new-var)))))))

;; proof-to-extracted-term gets either a proof or else a theorem name.
;; In the former case it works its way through the proof, until it
;; comes to an assumption variable, an axiom, a theorem or a global
;; assumption.  When it is a theorem, theorem-to-extracted-term is
;; called.  This also happens in the latter case above, when a theorem
;; name is the input.  theorem-to-extracted-term applies as default
;; theorem-or-global-assumption-to-pconst, where in case of a lemma L
;; the pconst has name cL.  It will unfold under normalization if the
;; lemma is animated.  However, in some cases theorem-to-extracted-term
;; directly gives short and meaningful terms:

;; obsolete: InhabTotal -> (Inhab rho)

;; AllTotalIntro AllTotalElim AllncTotalIntro AllncTotalElim InvarEx
;; InvarAll ExTotalIntro ExTotalElim -> [x]x

;; Pconst+Total -> Pconst

;; Pconst+STotal -> the extract from the proof

;; AlgEqTotal -> [n,m]n=m

;; AlgETotal -> [n]E n

;; BooleIfTotal -> [free][if test arg1 arg2]

;; EqDCompat EqDCompatRev -> [x]x

;; Id -> [x]x in case unfold-let-flag is true.

(define (proof-to-extracted-term . opt-proof-or-thm-name-and-unfold-let-flag)
  (if
   (null? opt-proof-or-thm-name-and-unfold-let-flag)
   (proof-to-extracted-term (current-proof) #f)
   (let ((first (car opt-proof-or-thm-name-and-unfold-let-flag))
	 (rest (cdr opt-proof-or-thm-name-and-unfold-let-flag)))
     (if
      (null? rest)
      (if (or (proof-form? first) (string? first))
	  (let*  ((proof-or-thm-name first)
		  (proof (if (proof-form? proof-or-thm-name)
			     proof-or-thm-name
			     (theorem-name-to-proof proof-or-thm-name))))
	    (cond
	     ((formula-of-nulltype? (proof-to-formula proof)) 'eps)
	     ((string? proof-or-thm-name)
	      (theorem-to-extracted-term
	       (theorem-name-to-aconst proof-or-thm-name)
	       #f)) ;no unfolding of cId
	     (else (let ((avar-to-var (make-avar-to-var)))
		     (proof-to-extracted-term-aux proof avar-to-var #f)))))
					;else first is the unfold-let-flag
	  (let ((avar-to-var (make-avar-to-var)))
	    (proof-to-extracted-term-aux (current-proof) avar-to-var first)))
      (let ((unfold-let-flag (car rest)))
	(if (or (proof-form? first) (string? first))
	    (let*  ((proof-or-thm-name first)
		    (proof (if (proof-form? proof-or-thm-name)
			       proof-or-thm-name
			       (theorem-name-to-proof proof-or-thm-name))))
	      (cond
	       ((formula-of-nulltype? (proof-to-formula proof)) 'eps)
	       ((string? proof-or-thm-name)
		(theorem-to-extracted-term
		 (theorem-name-to-aconst proof-or-thm-name)
		 unfold-let-flag))
	       (else (let ((avar-to-var (make-avar-to-var)))
		       (proof-to-extracted-term-aux
			proof avar-to-var unfold-let-flag)))))
	    (myerror "proof-to-extracted-term"
		     "proof or theorem name expected"
		     first)))))))

(define (proof-to-extracted-term-aux proof avar-to-var unfold-let-flag)
  (case (tag proof)
    ((proof-in-avar-form)
     (make-term-in-var-form
      (avar-to-var (proof-in-avar-form-to-avar proof))))
    ((proof-in-aconst-form)
     (let ((aconst (proof-in-aconst-form-to-aconst proof)))
       (case (aconst-to-kind aconst)
	 ((axiom) (axiom-to-extracted-term aconst))
	 ((theorem) (theorem-to-extracted-term aconst unfold-let-flag))
	 ((global-assumption)
	  (global-assumption-to-extracted-term aconst avar-to-var))
	 (else (myerror "proof-to-extracted-term-aux"
			"unknown kind of aconst"
			(aconst-to-kind aconst))))))
    ((proof-in-imp-intro-form)
     (let* ((avar (proof-in-imp-intro-form-to-avar proof))
	    (avar-type (formula-to-et-type (avar-to-formula avar)))
	    (kernel (proof-in-imp-intro-form-to-kernel proof))
	    (kernel-term (proof-to-extracted-term-aux
			  kernel avar-to-var unfold-let-flag)))
       (if (nulltype? avar-type)
	   kernel-term
	   (make-term-in-abst-form (avar-to-var avar) kernel-term))))
    ((proof-in-imp-elim-form)
     (let* ((op (proof-in-imp-elim-form-to-op proof))
	    (arg (proof-in-imp-elim-form-to-arg proof))
	    (arg-type (formula-to-et-type (proof-to-formula arg)))
	    (op-term (proof-to-extracted-term-aux
		      op avar-to-var unfold-let-flag)))
       (if (nulltype? arg-type)
	   op-term
	   (make-term-in-app-form
	    op-term (proof-to-extracted-term-aux
		     arg avar-to-var unfold-let-flag)))))
    ((proof-in-impnc-intro-form)
     (proof-to-extracted-term-aux
      (proof-in-impnc-intro-form-to-kernel proof)
      avar-to-var unfold-let-flag))
    ((proof-in-impnc-elim-form)
     (proof-to-extracted-term-aux
      (proof-in-impnc-elim-form-to-op proof) avar-to-var unfold-let-flag))
    ((proof-in-and-intro-form)
     (let* ((left (proof-in-and-intro-form-to-left proof))
	    (right (proof-in-and-intro-form-to-right proof))
	    (left-type (formula-to-et-type (proof-to-formula left)))
	    (right-type (formula-to-et-type (proof-to-formula right))))
       (if (nulltype? left-type)
	   (proof-to-extracted-term-aux right avar-to-var unfold-let-flag)
	   (if (nulltype? right-type)
	       (proof-to-extracted-term-aux
		left avar-to-var unfold-let-flag)
	       (make-term-in-pair-form
		(proof-to-extracted-term-aux
		 left avar-to-var unfold-let-flag)
		(proof-to-extracted-term-aux
		 right avar-to-var unfold-let-flag))))))
    ((proof-in-and-elim-left-form)
     (let* ((kernel (proof-in-and-elim-left-form-to-kernel proof))
	    (formula (proof-to-formula kernel))
	    (left-type (formula-to-et-type (and-form-to-left formula)))
	    (right-type (formula-to-et-type (and-form-to-right formula)))
	    (kernel-term (proof-to-extracted-term-aux
			  kernel avar-to-var unfold-let-flag)))
       (if (or (nulltype? left-type) (nulltype? right-type))
	   kernel-term
	   (make-term-in-lcomp-form kernel-term))))
    ((proof-in-and-elim-right-form)
     (let* ((kernel (proof-in-and-elim-right-form-to-kernel proof))
	    (formula (proof-to-formula kernel))
	    (left-type (formula-to-et-type (and-form-to-left formula)))
	    (right-type (formula-to-et-type (and-form-to-right formula)))
	    (kernel-term (proof-to-extracted-term-aux
			  kernel avar-to-var unfold-let-flag)))
       (if (or (nulltype? left-type) (nulltype? right-type))
	   kernel-term
	   (make-term-in-rcomp-form kernel-term))))
    ((proof-in-all-intro-form)
     (let ((var (proof-in-all-intro-form-to-var proof))
	   (kernel (proof-in-all-intro-form-to-kernel proof)))
       (make-term-in-abst-form
	var (proof-to-extracted-term-aux kernel avar-to-var unfold-let-flag))))
    ((proof-in-all-elim-form)
     (let ((op (proof-in-all-elim-form-to-op proof))
	   (arg (proof-in-all-elim-form-to-arg proof)))
       (make-term-in-app-form
	(proof-to-extracted-term-aux op avar-to-var unfold-let-flag) arg)))
    ((proof-in-allnc-intro-form)
     (let ((kernel (proof-in-allnc-intro-form-to-kernel proof)))
       (proof-to-extracted-term-aux kernel avar-to-var unfold-let-flag)))
    ((proof-in-allnc-elim-form)
     (let ((op (proof-in-allnc-elim-form-to-op proof)))
       (proof-to-extracted-term-aux op avar-to-var unfold-let-flag)))
    (else (myerror "proof-to-extracted-term-aux"
		   "proof tag expected" (tag proof)))))

(define (axiom-to-extracted-term aconst)
  (let ((name (aconst-to-name aconst)))
    (cond
     ((string=? "Ind" name)
      (make-term-in-const-form
       (apply all-formulas-to-et-rec-const
	      (aconst-to-repro-data aconst))))
     ((string=? "Cases" name)
      (cases-aconst-to-if-term aconst))
     ((string=? "GInd" name)
      (make-term-in-const-form
       (gind-aconst-to-et-grecguard-const aconst)))
     ((string=? "Intro" name)
      (let* ((number-and-idpc (aconst-to-repro-data aconst))
	     (idpc (cadr number-and-idpc))
	     (name (idpredconst-to-name idpc))
	     (opt-alg-name (idpredconst-name-to-opt-alg-name name))
	     (string (if (pair? opt-alg-name)
			 (car opt-alg-name)
			 (myerror "axiom-to-extracted-term"
				  "opt-alg-name expected"
				  idpc))))
	(apply number-and-idpredconst-to-et-constr-term number-and-idpc)))
     ((string=? "Elim" name)
      (let* ((uninst-fla (aconst-to-uninst-formula aconst))
	     (kernel (all-allnc-form-to-final-kernel uninst-fla))
	     (prems (imp-impnc-form-to-premises kernel))
	     (idpc-fla (if (pair? prems) (car prems)
			   (myerror "axiom-to-extracted-term"
				    "imp premises expected in"
				    kernel)))
	     (pred (if (predicate-form? idpc-fla)
		       (predicate-form-to-predicate idpc-fla)
		       (myerror "axiom-to-extracted-term"
				"predicate formula expected"
				idpc-fla)))
	     (idpc-name (if (idpredconst-form? pred)
			    (idpredconst-to-name pred)
			    (myerror "axiom-to-extracted-term"
				     "idpredconst expected" pred)))
	     (opt-alg-name (idpredconst-name-to-opt-alg-name idpc-name))
	     (clauses (idpredconst-name-to-clauses idpc-name)))
	(cond ;uniform one-clause defined idpc
	 ((and ;invariant idpc
	   (null? (idpredconst-name-to-opt-alg-name idpc-name))
	   (or ;either a special one allowing arbitrary conclusions
					;(to be extended to e.g. EvenMR)
	    (member idpc-name '("EqD" "ExU" "AndU"))
					;or a uniform one-clause defined idpc
	    (and (= 1 (length clauses))
		 (predicate-form?
		  (impnc-form-to-final-conclusion
		   (allnc-form-to-final-kernel (car clauses)))))))
	  (let* ;then the extracted term is an identity
	      ((tpsubst (aconst-to-tpsubst aconst))
	       (concl (imp-impnc-form-to-final-conclusion kernel))
	       (subst-concl (formula-substitute concl tpsubst))
	       (val-type (if (not (formula-of-nulltype? subst-concl))
			     (formula-to-et-type subst-concl)
			     (myerror "axiom-to-extracted-term"
				      "formula with content expected"
				      subst-concl)))
	       (var (type-to-new-var val-type)))
	    (make-term-in-abst-form var (make-term-in-var-form var))))
	 ((and ;identity idpc
	   (pair? opt-alg-name)
	   (string=? "identity" (car opt-alg-name)))
	  (let* ((imp-formulas (aconst-to-repro-data aconst))
		 (imp-formula (car imp-formulas))
		 (prem (imp-form-to-premise imp-formula))
		 (idpc (predicate-form-to-predicate prem))
		 (arg-type (idpredconst-to-et-type idpc))
		 (tpsubst (aconst-to-tpsubst aconst))
		 (concl (imp-impnc-form-to-final-conclusion kernel))
		 (subst-concl (formula-substitute concl tpsubst))
		 (val-type
		  (if (not (formula-of-nulltype? subst-concl))
		      (formula-to-et-type subst-concl)
		      (myerror "axiom-to-extracted-term"
			       "formula with content expected"
			       subst-concl))))
	    (if (nulltype? arg-type) ;then the extracted term is [b]b
		(let ((b (type-to-new-var val-type)))
		  (make-term-in-abst-form
		   b (make-term-in-var-form b)))
					;else the extracted term is [x,f]f x
		(let ((x (type-to-new-var arg-type))
		      (f (type-to-new-var
			  (make-arrow arg-type val-type))))
		  (mk-term-in-abst-form
		   x f (make-term-in-app-form
			(make-term-in-var-form f)
			(make-term-in-var-form x)))))))
	 (else ;default case
	  (make-term-in-const-form
	   (apply imp-formulas-to-et-rec-const
		  (aconst-to-repro-data aconst)))))))
     ((string=? "Closure" name)
      (let* ((tpsubst (aconst-to-tpsubst aconst))
     	     (tsubst
	      (map
	       (lambda (x)
		 (if (pvar-form? (car x))
		     (list (PVAR-TO-TVAR (car x))
			   (formula-to-et-type (cterm-to-formula (cadr x))))
		     x))
	       tpsubst))
     	     (uninst-fla (aconst-to-uninst-formula aconst))
     	     (kernel (all-allnc-form-to-final-kernel uninst-fla))
     	     (prem (imp-form-to-premise kernel))
     	     (uninst-alg
	      (if (not (formula-of-nulltype? prem))
		  (formula-to-et-type prem)
		  (myerror "axiom-to-extracted-term"
			   "formula with computational content expected" prem)))
     	     (alg (type-substitute uninst-alg tsubst)))
     	(make-term-in-const-form (alg-to-destr-const alg))))
     ((string=? "Gfp" name)
      (let* ((inst-fla (aconst-to-inst-formula aconst))
	     (et-type (formula-to-et-type inst-fla))
	     (alg (arrow-form-to-final-val-type et-type))
	     (alg-name (if (alg-form? alg)
			   (alg-form-to-name alg)
			   (myerror "axiom-to-extracted-term"
				    "algebra form expected" alg)))
	     (alg-types (alg-form-to-types alg))
	     (simalg-names (alg-name-to-simalg-names alg-name))
	     (arg-types (arrow-form-to-arg-types et-type))
	     (improper-corec? (= (length simalg-names)
				 (length arg-types)))
	     (uninst-step-types (if improper-corec?
				    arg-types
				    (cdr arg-types)))
	     (f-or-types (map (lambda (type)
				(if (arrow-form? type)
				    (arrow-form-to-arg-type type)
				    #f))
			      uninst-step-types))
	     (alg-or-arrow-types
	      (map (lambda (f-or-type simalg-name)
		     (if f-or-type
			 (make-arrow
			  f-or-type
			  (apply make-alg
				 (cons simalg-name alg-types)))
			 (apply make-alg
				(cons simalg-name alg-types))))
		   f-or-types simalg-names))
	     (alg-or-arrow-type
	      (if improper-corec?
		  alg
		  (make-arrow (car arg-types) alg)))
	     (rest-alg-or-arrow-types
	      (remove alg-or-arrow-type alg-or-arrow-types))
	     (corec-const (apply alg-or-arrow-types-to-corec-const
				 (cons alg-or-arrow-type
				       rest-alg-or-arrow-types))))
	(make-term-in-const-form corec-const)))
     ((string=? "Ex-Intro" name)
      (ex-formula-to-ex-intro-et (car (aconst-to-repro-data aconst))))
     ((string=? "Ex-Elim" name)
      (apply ex-formula-and-concl-to-ex-elim-et (aconst-to-repro-data aconst)))
     ((string=? "InvarEx" name)
      (let* ((imp-fla (aconst-to-uninst-formula invarex-aconst))
	     (exl-fla (imp-form-to-conclusion imp-fla))
	     (var (exl-form-to-var exl-fla)))
	(make-term-in-abst-form var (make-term-in-var-form var))))
     ((string=? "InvarAll" name)
      (let* ((all-fla (aconst-to-uninst-formula invarall-aconst))
	     (var (all-form-to-var all-fla)))
	(make-term-in-abst-form var (make-term-in-var-form var))))
     ((member name '("ExTotalIntro" "ExTotalElim"
		     "ExDTotalIntro" "ExLTotalIntro" "ExRTotalIntro"
		     ;; "ExDTotalElim" "ExLTotalElim" "ExRTotalElim"
		     "AllTotalIntro" "AllTotalElim"
		     "AllncTotalIntro" "AllncTotalElim"))
      (let* ((imp-fla (aconst-to-inst-formula aconst))
	     (prem (imp-form-to-premise imp-fla))
	     (type (formula-to-et-type prem))
	     (var (type-to-new-var type)))
	(make-term-in-abst-form var (make-term-in-var-form var))))
     ((string=? "InhabTotal" name) ;obsolete
      (let* ((formula (aconst-to-formula aconst))
	     (args (predicate-form-to-args formula)))
	(car args)))
     (else (myerror "axiom-to-extracted-term" "axiom expected" name)))))

(define (theorem-to-extracted-term aconst . opt-unfold-let-flag)
  (if
   (null? opt-unfold-let-flag)
   (theorem-to-extracted-term aconst #f)
   (let* ((unfold-let-flag (car opt-unfold-let-flag))
	  (thm-name (aconst-to-name aconst))
	  (proof (theorem-name-to-proof thm-name))
	  (tpsubst (aconst-to-tpsubst aconst))
	  (tsubst (list-transform-positive tpsubst
		    (lambda (x) (tvar-form? (car x)))))
	  (psubst (list-transform-positive tpsubst
		    (lambda (x) (pvar-form? (car x))))))
     (cond
      ((string=? "InhabTotal" thm-name)
       (let ((formula (aconst-to-formula aconst))) ;Total(Inhab rho)
	 (car (predicate-form-to-args formula))))
      ((member thm-name (list "AllTotalIntro" "AllTotalElim"
			      "AllncTotalIntro" "AllncTotalElim"
			      ;; "MRIntro" "MRElim"
			      "ExTotalIntro" "ExTotalElim"))
       (let* ((formula (unfold-formula (aconst-to-formula aconst)))
	      (type (formula-to-et-type formula))
	      (arg-type (if (arrow-form? type)
			    (arrow-form-to-arg-type type)
			    (myerror "theorem-to-extracted-term"
				     "arrow type expected" type)))
	      (var (type-to-new-partial-var arg-type)))
	 (make-term-in-abst-form var (make-term-in-var-form var))))
      ((final-substring? "TotalVar" thm-name)
       (let* ((formula (unfold-formula (aconst-to-formula aconst)))
	      (type (var-to-type (all-form-to-var formula)))
	      (var (type-to-new-partial-var type)))
	 (make-term-in-abst-form var (make-term-in-var-form var))))
      ((and (final-substring? "Total" thm-name)
	    (pconst-name? (substring thm-name 0 (- (string-length thm-name)
						   (string-length "Total")))))
       (let* ((pconst (pconst-name-to-pconst
		       (substring thm-name 0 (- (string-length thm-name)
						(string-length "Total")))))
	      (subst-pconst (const-substitute pconst tsubst #t)))
	 (make-term-in-const-form subst-pconst)))
      ((and (final-substring? "STotal" thm-name)
	    (pconst-name? (substring thm-name 0 (- (string-length thm-name)
						   (string-length "STotal")))))
       (proof-to-extracted-term proof))
      ((and (final-substring? "EqTotal" thm-name)
	    (assoc (string-downcase
		    (substring thm-name 0 (- (string-length thm-name)
					     (string-length "EqTotal"))))
		   ALGEBRAS))
       (let* ((formula (aconst-to-formula aconst))
	      (concl (imp-impnc-all-allnc-form-to-final-conclusion formula))
	      (arg (if (predicate-form? concl)
		       (car (predicate-form-to-args concl))
		       (myerror "theorem-to-extracted-term"
				"predicate form expected" concl)))
	      (free (term-to-free arg))
	      (type (if (pair? free)
			(var-to-type (car free))
			(myerror "theorem-to-extracted-term"
				 "free variables expected in" arg))))
	 (if (not (finalg? type))
	     (myerror "theorem-to-extracted-term"
		      "finalg variable expected" (car free)))
	 (apply mk-term-in-abst-form (append free (list arg)))))
      ((and (final-substring? "ETotal" thm-name)
	    (assoc (string-downcase
		    (substring thm-name 0 (- (string-length thm-name)
					     (string-length "ETotal"))))
		   ALGEBRAS))
       (let* ((formula (aconst-to-formula aconst))
	      (concl (imp-impnc-all-allnc-form-to-final-conclusion formula))
	      (arg (if (predicate-form? concl)
		       (car (predicate-form-to-args concl))
		       (myerror "theorem-to-extracted-term"
				"predicate form expected" concl)))
	      (free (term-to-free arg))
	      (type (if (pair? free)
			(var-to-type (car free))
			(myerror "theorem-to-extracted-term"
				 "free variables expected in" arg))))
	 (if (not (finalg? type))
	     (myerror "theorem-to-extracted-term"
		      "finalg variable expected" (car free)))
	 (apply mk-term-in-abst-form (append free (list arg)))))
      ((string=? "BooleIfTotal" thm-name)
       (let* ((formula (aconst-to-formula aconst))
	      (concl (imp-impnc-all-allnc-form-to-final-conclusion formula))
	      (args (if (predicate-form? concl)
			(predicate-form-to-args concl)
			(myerror "theorem-to-extracted-term"
				 "predicate form expected" concl)))
	      (if-term (if (pair? args) (car args)
			   (myerror "theorem-to-extracted-term"
				    "arguments expected" concl)))
	      (free (term-to-free if-term)))
	 (apply mk-term-in-abst-form (append free (list if-term)))))
      ((or (member thm-name (list "EqDCompat" "EqDCompatRev"))
	   (and (string=? thm-name "Id") unfold-let-flag))
       (let* ((uninst-formula (aconst-to-uninst-formula aconst))
	      (concl (imp-impnc-all-allnc-form-to-final-conclusion
		      uninst-formula))
	      (pvar (predicate-form-to-predicate concl))
	      (cterm (let ((info (assoc pvar tpsubst)))
		       (if info (cadr info)
			   (predicate-to-cterm pvar))))
	      (cterm-formula (cterm-to-formula cterm))
	      (et-type (formula-to-et-type cterm-formula))
	      (var (if (nulltype? et-type)
		       (myerror "theorem-to-extracted-term"
				"computationally relevant formula expected"
				formula)
		       (type-to-new-partial-var et-type))))
	 (make-term-in-abst-form var (make-term-in-var-form var))))
      (else (make-term-in-const-form
	     (theorem-or-global-assumption-to-pconst aconst)))))))

(define (global-assumption-to-extracted-term aconst avar-to-var)
  (let* ((name (aconst-to-name aconst))
	 (info (assoc name GLOBAL-ASSUMPTIONS)))
    (if
     info
     (cond
      ((string=? "StabLog" name)
       (let* ((formula (unfold-formula (aconst-to-formula aconst)))
	      (kernel (allnc-form-to-final-kernel formula))
	      (concl (imp-form-to-conclusion kernel)))
	 (case (tag concl)
	   ((atom predicate ex)
	    (if
	     (not (equal? falsity-log concl))
	     (let* ((pconst
		     (theorem-or-global-assumption-to-pconst aconst))
		    (term (make-term-in-const-form pconst)))
	       (comment "StabLog realized by ad hoc term "
			(term-to-string term))
	       term) ;else first unfold
	     (proof-to-extracted-term-aux
	      (proof-of-stab-log-at concl) avar-to-var #f)))
	   ((imp impnc and all allnc) ;first unfold
	    (proof-to-extracted-term-aux
	     (proof-of-stab-log-at concl) avar-to-var #f))
	   (else (myerror "global-assumption-to-extracted-term"
			  "formula expected"
			  concl)))))
      ((string=? "EfqLog" name)
       (let* ((formula (unfold-formula (aconst-to-formula aconst)))
	      (kernel (allnc-form-to-final-kernel formula))
	      (concl (imp-form-to-conclusion kernel)))
	 (case (tag concl)
	   ((atom predicate ex)
	    (if (not (equal? falsity-log concl))
		(let* ((pconst
			(theorem-or-global-assumption-to-pconst aconst))
		       (term (make-term-in-const-form pconst)))
		  (comment "EfqLog realized by ad hoc term "
			   (term-to-string term))
		  term) ;else first unfold
		(proof-to-extracted-term-aux
		 (proof-of-efq-log-at concl) avar-to-var #f)))
	   ((imp impnc and all allnc) ;first unfold
	    (proof-to-extracted-term-aux
	     (proof-of-efq-log-at concl) avar-to-var #f))
	   (else (myerror
		  "global-assumption-to-extracted-term" "formula expected"
		  concl)))))
      ((string=? "Efq" name)
       (let* ((formula (aconst-to-formula aconst))
	      (etype (formula-to-et-type formula)))
	 (type-to-canonical-inhabitant etype)))
      ((or (and (<= (string-length "Compat-Rev")
		    (string-length name))
		(string=?
		 (substring name 0 (string-length "Compat-Rev"))
		 "Compat-Rev"))
	   (and (<= (string-length "Compat")
		    (string-length name))
		(string=?
		 (substring name 0 (string-length "Compat"))
		 "Compat")))
       (let* ((formula (unfold-formula (aconst-to-formula aconst)))
	      (type (formula-to-et-type formula))
	      (arg-type (if (arrow-form? type)
			    (arrow-form-to-arg-type type)
			    (myerror "global-assumption-to-extracted-term"
				     "arrow type expected"
				     type)))
	      (var (type-to-new-partial-var arg-type)))
	 (make-term-in-abst-form var (make-term-in-var-form var))))
      (else
       (make-term-in-const-form
	(theorem-or-global-assumption-to-pconst aconst))))
     (myerror "global-assumption-to-extracted-term"
	      "global assumption expected"
	      name))))

(define (all-formulas-to-et-rec-const . all-formulas)
  (if (nested-alg-name?
       (alg-form-to-name (var-to-type (all-form-to-var (car all-formulas)))))
      (myerror "all-formulas-to-et-rec-const"
	       "all-formula for an unnested algebra expected"
	       (car all-formulas)
	       "unfold all-formula and use imp-formulas-to-elim-aconst"))
  (let* ((uninst-imp-formulas-and-tpsubst
	  (apply all-formulas-to-uninst-imp-formulas-and-tpsubst all-formulas))
	 (uninst-imp-formulas (car uninst-imp-formulas-and-tpsubst))
	 (tpsubst (cadr uninst-imp-formulas-and-tpsubst))
	 (tsubst (list-transform-positive tpsubst
		   (lambda (x) (tvar-form? (car x)))))
	 (psubst (list-transform-positive tpsubst
		  (lambda (x) (pvar-form? (car x)))))
	 (relevant-psubst (list-transform-positive psubst
			   (lambda (x)
			     (not (formula-of-nulltype?
				   (cterm-to-formula (cadr x)))))))
	 (pvars (map car relevant-psubst))
	 (cterms (map cadr relevant-psubst))
	 (et-types (map (lambda (cterm)
			  (formula-to-et-type (cterm-to-formula cterm)))
			cterms))
	 (new-tvars (map PVAR-TO-TVAR pvars))
	 (new-tsubst (make-substitution new-tvars et-types))
	 (uninst-recop-types (map formula-to-et-type uninst-imp-formulas))
	 (vars (map all-form-to-var all-formulas))
	 (types (map var-to-type vars))
	 (alg-names
	  (map (lambda (type)
		 (if (alg-form? type)
		     (alg-form-to-name type)
		     (myerror "all-formulas-to-et-rec-const" "alg expected"
			      type)))
	       types))
	 (alg-names-with-uninst-recop-types
	  (map list alg-names uninst-recop-types))
	 (simalg-names (alg-name-to-simalg-names (car alg-names)))
	 (sorted-alg-names (list-transform-positive simalg-names
			     (lambda (x) (member x alg-names))))
	 (typed-constr-names
	  (apply append
		 (map alg-name-to-typed-constr-names sorted-alg-names)))
	 (constr-names (map typed-constr-name-to-name typed-constr-names))
	 (alg-name (car alg-names))
	 (uninst-recop-type
	  (cadr (assoc alg-name alg-names-with-uninst-recop-types)))
	 (inst-recop-type (type-substitute uninst-recop-type
					   (append tsubst new-tsubst))))
    (alg-name-etc-to-rec-const
     alg-name uninst-recop-type (append tsubst new-tsubst) inst-recop-type
     0 constr-names alg-names-with-uninst-recop-types)))

(define (cases-aconst-to-if-term aconst)
  (let* ((uninst-imp-formula (aconst-to-uninst-formula aconst))
	 (tpsubst (aconst-to-tpsubst aconst))
	 (tsubst (list-transform-positive tpsubst
		   (lambda (x) (tvar-form? (car x)))))
	 (psubst (list-transform-positive tpsubst
		   (lambda (x) (pvar-form? (car x)))))
	 (relevant-psubst (list-transform-positive psubst
			    (lambda (x)
			      (not (formula-of-nulltype?
				    (cterm-to-formula (cadr x)))))))
	 (pvars (map car relevant-psubst))
	 (cterms (map cadr relevant-psubst))
	 (et-types (map (lambda (cterm)
			  (formula-to-et-type
			   (cterm-to-formula cterm)))
			cterms))
	 (new-tvars (map PVAR-TO-TVAR pvars))
	 (new-tsubst (make-substitution new-tvars et-types))
	 (uninst-casesop-type (formula-to-et-type uninst-imp-formula))
	 (s ;number of step types
	  (- (length (arrow-form-to-arg-types uninst-casesop-type)) 1))
	 (inst-casesop-type
	  (type-substitute uninst-casesop-type (append tsubst new-tsubst)))
	 (alt-types
          (cdr (arrow-form-to-arg-types inst-casesop-type (+ s 1))))
	 (test-type (arrow-form-to-arg-type inst-casesop-type))
	 (alt-vars (map type-to-new-var alt-types))
	 (test-var (type-to-new-var test-type)))
    (apply mk-term-in-abst-form
	   test-var
	   (append alt-vars
		   (list (make-term-in-if-form
			  (make-term-in-var-form test-var)
			  (map make-term-in-var-form alt-vars)))))))

(define (gind-aconst-to-et-grecguard-const aconst)
  (let* ((uninst-gind-formula (aconst-to-uninst-formula aconst))
         (measure-var-and-vars (all-form-to-vars uninst-gind-formula))
         (vars (cdr measure-var-and-vars))
         (m (length vars))
         (tpsubst (aconst-to-tpsubst aconst))
         (tsubst (list-transform-positive tpsubst
                   (lambda (x) (tvar-form? (car x)))))
         (pvar-and-cterm
          (list-search-positive tpsubst
            (lambda (x) (pvar-form? (car x)))))
         (cterm (cadr pvar-and-cterm))
         (et-type (formula-to-et-type (cterm-to-formula cterm)))
         (arg-types (map var-to-type vars))
	 (subst-arg-types (map (lambda (type) (type-substitute type tsubst))
			       arg-types))
         (type-info (append subst-arg-types (list et-type))))
    (type-info-to-grecguard-const type-info)))

;; Terminology:
;; clause            - with assigned predicate variable instead of the idpc
;; uninst-intro-fla  - with idpc substituted, but still with tvars, param-pvars
;; intro-fla         - fully substituted

(define (number-and-idpredconst-to-et-constr-term i idpc)
  (let* ((name (idpredconst-to-name idpc))
	 (opt-alg-name (idpredconst-name-to-opt-alg-name name))
	 (alg-name (if (pair? opt-alg-name) (car opt-alg-name)
		       (myerror "number-and-idpredconst-to-et-constr-term"
				"alg name expected for" name)))
	 (clauses (idpredconst-name-to-clauses name))
	 (clause
	  (if (and (integer? i) (not (negative? i)) (< i (length clauses)))
	      (list-ref clauses i)
	      (myerror "number-and-idpredconst-to-et-constr-term" i
		       "should be an index of a clause for" name)))
	 (clauses-with-names (idpredconst-name-to-clauses-with-names name))
	 (clause-with-name (list-ref clauses-with-names i))
	 (types (idpredconst-to-types idpc))
	 (cterms (idpredconst-to-cterms idpc))
	 (tvars (idpredconst-name-to-tvars name))
	 (idpc-pvars (idpredconst-name-to-pvars name))
	 (param-pvars (idpredconst-name-to-param-pvars name))
	 (simidpc-names (idpredconst-name-to-simidpc-names name))
	 (simidpc-clauses
	  (apply union (map idpredconst-name-to-clauses simidpc-names)))
	 (simidpc-et-types (map formula-to-et-type simidpc-clauses))
	 (simidpc-et-tvars
	  (set-minus (apply union (map type-to-tvars simidpc-et-types))
		     idpc-pvars))
	 (relevant-types (do ((l1 tvars (cdr l1))
			      (l2 types (cdr l2))
			      (res '() (let ((tvar (car l1))
					     (type (car l2)))
					 (if (member tvar simidpc-et-tvars)
					     (cons type res)
					     res))))
			     ((null? l2) (reverse res))))
	 (relevant-cterm-types
	  (do ((l1 param-pvars (cdr l1))
	       (l2 cterms (cdr l2))
	       (res '() (let* ((pvar (car l1))
			       (cterm (car l2))
			       (formula (cterm-to-formula cterm))
			       (cterm-et-type (formula-to-et-type formula)))
			  (if (and
			       (pvar-with-positive-content? pvar)
			       (member (PVAR-TO-TVAR pvar) simidpc-et-tvars))
			      (cons cterm-et-type res)
			      res))))
	      ((null? l1) (reverse res))))
	 (val-types (append relevant-types relevant-cterm-types))
	 (nc-indicator (map nulltype? val-types))
	 (alg-name-et
	  (alg-name-and-nc-indicator-to-alg-name alg-name nc-indicator)))
    (cond
     ((string=? "identity" alg-name-et)
      (let* ((et-type (idpredconst-to-et-type idpc))
	     (var (type-to-new-partial-var et-type)))
	(make-term-in-abst-form var (make-term-in-var-form var))))
     ((string=? "nulltype" alg-name-et) 'eps)
     (else
      (let* ((known-alg-name?
	      (not (string=? (string-append "alg" name) alg-name)))
	     (alg-tvars (alg-name-to-tvars alg-name))
	     (tsubst (make-substitution alg-tvars val-types))
	     (constr-name
	      (cond
	       (known-alg-name?
		(car (list-ref (alg-name-to-typed-constr-names alg-name-et) i)))
	       ((< 1 (length clause-with-name))
		(let ((suffixes
		       (if (string=? alg-name alg-name-et)
			   '()
			   (map (lambda (b) (if b "Nc" "Cr")) nc-indicator))))
		  (apply string-append "C" (cadr clause-with-name) suffixes)))
	       (else (myerror "number-and-idpredconst-to-et-constr-term"
			      "constr name missing for" clause))))
	     (constr (constr-name-to-constr constr-name))
	     (subst-constr (const-substitute constr tsubst #t)))
	(make-term-in-const-form subst-constr))))))

;; imp-formulas is a list of formulas I xs^ -> A[xs^].  uninst-elim-formula
;; is Ij xs^ -> K1[Xs,Ps] -> .. -> Kk[Xs,Ps] -> Pj xs^

(define (imp-formulas-to-et-rec-const . imp-formulas)
  (let* ((uninst-elim-formulas-etc
	  (apply imp-formulas-to-uninst-elim-formulas-etc imp-formulas))
	 (uninst-elim-formulas (car uninst-elim-formulas-etc))
	 (tsubst (cadr uninst-elim-formulas-etc))
	 (psubst-for-param-pvars (caddr uninst-elim-formulas-etc))
	 (psubst-for-pvars (cadddr uninst-elim-formulas-etc))
	 (uninst-recop-types (map formula-to-et-type uninst-elim-formulas))
	 (idpc-names (map (lambda (uninst-elim-formula)
			    (idpredconst-to-name
			     (predicate-form-to-predicate
			      (imp-form-to-premise uninst-elim-formula))))
			  uninst-elim-formulas))
	 (alg-names (map idpredconst-name-to-alg-name idpc-names))
	 (alg-names-with-uninst-recop-types
	  (map list alg-names uninst-recop-types))
	 (uninst-recop-type (car uninst-recop-types))
	 (alg-name (car alg-names))
	 (param-pvar-cterms (map cadr psubst-for-param-pvars))
	 (param-pvar-formulas (map cterm-to-formula param-pvar-cterms))
	 (param-pvar-et-types (map formula-to-et-type param-pvar-formulas))
	 (param-pvar-tsubst
	  (map (lambda (x param-pvar-et-type) ;x pair in psubst-for-param-pvars
		 (let* ((param-pvar (car x))
			(tvar (PVAR-TO-TVAR param-pvar)))
		   (list tvar param-pvar-et-type)))
	       psubst-for-param-pvars param-pvar-et-types))
	 (pvar-cterm-et-types
	  (map (lambda (cterm) (formula-to-et-type (cterm-to-formula cterm)))
	       (map cadr psubst-for-pvars)))
	 (pvar-tsubst
	  (map (lambda (x y) (let* ((pvar (car x))
				    (tvar (PVAR-TO-TVAR pvar)))
			       (list tvar y)))
	       psubst-for-pvars pvar-cterm-et-types))
	 (inst-recop-type
	  (type-substitute uninst-recop-type
			   (append tsubst param-pvar-tsubst pvar-tsubst)))
	 (simalg-names (alg-name-to-simalg-names alg-name))
	 (sorted-alg-names (list-transform-positive simalg-names
			     (lambda (x) (member x alg-names))))
	 (typed-constr-names
	  (apply append
		 (map alg-name-to-typed-constr-names sorted-alg-names)))
	 (constr-names (map typed-constr-name-to-name typed-constr-names)))
    (alg-name-etc-to-rec-const
     alg-name uninst-recop-type
     (append tsubst param-pvar-tsubst pvar-tsubst)
     inst-recop-type 0 constr-names
     alg-names-with-uninst-recop-types)))

(define (ex-formula-to-ex-intro-et ex-formula)
  (let* ((var (ex-form-to-var ex-formula))
         (kernel (ex-form-to-kernel ex-formula))
	 (kernel-type (formula-to-et-type kernel)))
    (if (nulltype? kernel-type)
	(make-term-in-abst-form var (make-term-in-var-form var))
	(let ((new-var (type-to-new-var kernel-type)))
	  (mk-term-in-abst-form
	   var new-var (make-term-in-pair-form
			(make-term-in-var-form var)
			(make-term-in-var-form new-var)))))))

(define (ex-formula-and-concl-to-ex-elim-et ex-formula concl)
  (let* ((var (ex-form-to-var ex-formula))
	 (type (var-to-type var))
         (kernel (ex-form-to-kernel ex-formula))
	 (kernel-type (formula-to-et-type kernel))
	 (ex-type (formula-to-et-type ex-formula))
	 (concl-type (formula-to-et-type concl)))
    (if (nulltype? kernel-type)
	(let* ((fct-type (make-arrow type concl-type))
	       (fct-var (type-to-new-var fct-type)))
	  (mk-term-in-abst-form
	   var fct-var (make-term-in-app-form
			(make-term-in-var-form fct-var)
			(make-term-in-var-form var))))
	(let* ((fct-type (mk-arrow type kernel-type concl-type))
	       (fct-var (type-to-new-var fct-type))
	       (pair-var (type-to-new-var (make-star type kernel-type)))
	       (pair-var-term (make-term-in-var-form pair-var)))
	  (mk-term-in-abst-form
	   pair-var fct-var
	   (mk-term-in-app-form
	    (make-term-in-var-form fct-var)
	    (make-term-in-lcomp-form pair-var-term)
	    (make-term-in-rcomp-form pair-var-term)))))))

;; Moreover we initially supply the identity theorem Id: Pvar -> Pvar.
;; This can be done only here, because for add-theorem we need
;; formula-to-et-type.

(define id-proof
  (let* ((pvar (mk-pvar (make-arity)))
	 (predicate-formula (make-predicate-formula pvar))
	 (avar (make-avar predicate-formula -1 "")))
    (make-proof-in-imp-intro-form
     avar (make-proof-in-avar-form avar))))

(add-theorem "Id" id-proof)

;; Usage: When an object (value of a variable or realizer of a premise)
;; might be used more than once, make sure (if necessary by a cut) that
;; the goal has the form A -> B or all x A.  Now use Id: P -> P.
;; (use-with "Id" (make-cterm (goal-to-formula (current-goal))) "?") is
;; often preferable, since (use "Id") can take a long time.  Its
;; realizer then has the form [f,x]f x.  If cId is not animated, one
;; obtains cId([x]body)arg, to be written [let x arg body].  When cId
;; is animated, normalization substitutes arg for x in body.

;; (animate "Id")
;; ;; ok, computation rule (cId alpha3) -> [(alpha3)_0](alpha3)_0 added
;; (deanimate "Id")

;; We add some initial inductive definitions.  This can be done only
;; here, since their clauses are added as theorems and might be c.r.

(set! COMMENT-FLAG #f)

(add-ids (list (list "EqD" (make-arity (py "alpha") (py "alpha"))))
	 '("allnc alpha^ EqD alpha^ alpha^" "InitEqD"))

(add-ids (list (list "ExD" (make-arity) "yprod"))
	 '("all alpha^((Pvar alpha)alpha^ -> ExD)" "InitExD"))

(add-ids (list (list "ExL" (make-arity) "identity"))
	 '("all alpha^((Pvar alpha)alpha^ --> ExL)" "InitExL"))

(add-ids (list (list "ExR" (make-arity) "identity"))
	 '("allnc alpha^((Pvar alpha)alpha^ -> ExR)" "InitExR"))

(add-ids (list (list "ExU" (make-arity)))
	 '("allnc alpha^((Pvar alpha)alpha^ --> ExU)" "InitExU"))

(add-ids (list (list "ExDT" (make-arity) "yprod"))
	 '("all alpha((Pvar alpha)alpha -> ExDT)" "InitExDT"))

(add-ids (list (list "ExLT" (make-arity) "identity"))
	 '("all alpha((Pvar alpha)alpha --> ExLT)" "InitExLT"))

(add-ids (list (list "ExRT" (make-arity) "identity"))
	 '("allnc alpha((Pvar alpha)alpha -> ExRT)" "InitExRT"))

(add-ids (list (list "ExUT" (make-arity)))
	 '("allnc alpha((Pvar alpha)alpha --> ExUT)" "InitExUT"))

(add-ids (list (list "AndD" (make-arity) "yprod"))
	 '("Pvar1 -> Pvar2 -> AndD" "InitAndD"))

(add-ids (list (list "AndL" (make-arity) "identity"))
 	 '("Pvar1 -> Pvar2 --> AndL" "InitAndL"))

(add-ids (list (list "AndR" (make-arity) "identity"))
	 '("Pvar1 --> Pvar2 -> AndR" "InitAndR"))

(add-ids (list (list "AndU" (make-arity)))
	 '("Pvar1 --> Pvar2 --> AndU" "InitAndU"))

(add-ids (list (list "OrD" (make-arity) "ysum"))
	 '("Pvar1 -> OrD" "InlOrD")
	 '("Pvar2 -> OrD" "InrOrD"))

(add-ids (list (list "OrR" (make-arity) "uysum"))
	 '("Pvar1 --> OrR" "InlOrR")
	 '("Pvar2 -> OrR" "InrOrR"))

(add-ids (list (list "OrL" (make-arity) "ysumu"))
	 '("Pvar1 -> OrL" "InlOrL")
	 '("Pvar2 --> OrL" "InrOrL"))

;; OrU has computational content, because we know on which side we are.

(add-ids (list (list "OrU" (make-arity) "boole"))
	 '("Pvar1 --> OrU" "InlOrU")
	 '("Pvar2 --> OrU" "InrOrU"))

(add-ids (list (list "OrNc" (make-arity)))
	 '("Pvar1 -> OrNc" "InlOrNc")
	 '("Pvar2 -> OrNc" "InrOrNc"))

(add-ids (list (list "ExPT" (make-arity) "algExPT"))
	 '("allnc alpha(Total alpha & (Pvar alpha)alpha -> ExPT)" "InitExPT"))

;; The computation rules for the constants introduced in boole.scm can
;; be added only here, since the construction of the proofs for their
;; rules needs EqD.

(add-computation-rules
 "AndConst True boole^" "boole^"
 "AndConst boole^ True" "boole^"
 "AndConst False boole^" "False"
 "AndConst boole^ False" "False")

(add-computation-rules
"ImpConst False boole^" "True"
"ImpConst True boole^" "boole^"
"ImpConst boole^ True" "True")

(add-computation-rules
"OrConst True boole^" "True"
"OrConst boole^ True" "True"
"OrConst False boole^" "boole^"
"OrConst boole^ False" "boole^")

(add-computation-rules
"NegConst True" "False"
"NegConst False" "True")

(add-computation-rule "lft(alpha1 pair alpha2)" "alpha1")

(add-computation-rule "rht(alpha1 pair alpha2)" "alpha2")

;; atom-to-eqd-true-aconst and eqd-true-to-atom-aconst can be added
;; only here, because they need EqD.

(define atom-to-eqd-true-aconst
  (make-aconst "AtomToEqDTrue" 'axiom
	       (pf "all boole^(boole^ -> boole^ eqd True)")
	       empty-subst))

(add-theorem "AtomToEqDTrue"
	     (make-proof-in-aconst-form atom-to-eqd-true-aconst))

(define eqd-true-to-atom-aconst
  (make-aconst "EqDTrueToAtom" 'axiom
	       (pf "all boole^(boole^ eqd True -> boole^)")
	       empty-subst))

(add-theorem "EqDTrueToAtom"
	     (make-proof-in-aconst-form eqd-true-to-atom-aconst))

(define truth-proof
  (let* ((idpc (make-idpredconst "EqD" (list (make-alg "boole")) '()))
	 (initeqd-aconst (number-and-idpredconst-to-intro-aconst 0 idpc)))
    (mk-proof-in-elim-form
     (make-proof-in-aconst-form eqd-true-to-atom-aconst)
     (make-term-in-const-form true-const)
     (mk-proof-in-elim-form
      (make-proof-in-aconst-form initeqd-aconst)
      (make-term-in-const-form true-const)))))

(add-theorem "Truth" truth-proof)

(define truth-aconst (theorem-name-to-aconst "Truth"))

;; atom-true-proof can be defined only here, because it needs EqD
;; atom-to-eqd-true-aconst and eqd-true-to-atom-aconst

(define atom-true-proof
  (let* ((type (make-alg "boole"))
	 (name (default-var-name type))
	 (var1 (make-var type 1 0 name))
	 (var2 (make-var type 2 0 name))
	 (varterm1 (make-term-in-var-form var1))
	 (varterm2 (make-term-in-var-form var2))
	 (u1 (formula-to-new-avar (make-atomic-formula varterm1)))
	 (eqd-fla (make-eqd varterm1 varterm2)) ;p^ eqd q^
	 (true-term (make-term-in-const-form true-const))
	 (fla1 (make-atomic-formula (make-=-term varterm1 true-term)))
	 (fla2 (make-atomic-formula (make-=-term varterm2 true-term)))
	 (imp-fla (mk-imp eqd-fla fla2 fla1))
	 (aconst (imp-formulas-to-elim-aconst imp-fla))
	 (var (make-var type -1 0 name))
	 (varterm (make-term-in-var-form var))
	 (fla (make-atomic-formula (make-=-term varterm true-term)))
	 (u (make-avar fla -1 "u"))
	 (idpc (make-idpredconst "EqD" (list (make-alg "boole")) '()))
	 (initeqd-aconst (number-and-idpredconst-to-intro-aconst 0 idpc)))
    (mk-proof-in-intro-form
     var1 u1 (mk-proof-in-elim-form
	      (make-proof-in-aconst-form aconst)
	      varterm1 true-term
	      (mk-proof-in-elim-form ;p^ eqd True
	       (make-proof-in-aconst-form atom-to-eqd-true-aconst)
	       varterm1 (make-proof-in-avar-form u1))
	      (make-proof-in-allnc-intro-form ;allnc q^(q^ =True -> p^ =True)
	       var (make-proof-in-imp-intro-form
		    u (make-proof-in-avar-form u)))
	      (mk-proof-in-elim-form ;atom True
	       (make-proof-in-aconst-form eqd-true-to-atom-aconst)
	       true-term
	       (mk-proof-in-elim-form
		(make-proof-in-aconst-form initeqd-aconst)
		(make-term-in-const-form true-const)))))))

(add-theorem "AtomTrue" atom-true-proof)

(define atom-true-aconst
  (make-aconst "AtomTrue" 'theorem
	       (pf "all boole^(boole^ -> boole^ =True)")
	       empty-subst))

;; atom-false-proof can be defined only here, because it needs truth-aconst

(define atom-false-proof
  (let* ((type (make-alg "boole"))
	 (name (default-var-name type))
	 (var (make-var type -1 t-deg-one name))
	 (varterm (make-term-in-var-form var))
	 (u1 (make-avar (pf "T -> F") 1  "u"))
	 (u2 (make-avar (pf "F -> F") 2  "u")))
    (make-proof-in-all-intro-form
     var (mk-proof-in-elim-form
	  (make-proof-in-aconst-form
	   (all-formula-to-cases-aconst
	    (pf "all boole((boole -> F) -> boole=False)")))
	  varterm
	  (mk-proof-in-intro-form
	   u1 (mk-proof-in-elim-form
	       (make-proof-in-avar-form u1)
	       (make-proof-in-aconst-form truth-aconst)))
	  (mk-proof-in-intro-form
	   u2 (make-proof-in-aconst-form truth-aconst))))))

(add-theorem "AtomFalse" atom-false-proof)

(define atom-false-aconst
  (make-aconst "AtomFalse" 'theorem
	       (pf "all boole((boole -> F) -> boole=False)")
	       empty-subst))

;; imp-to-atom-proof atom-to-imp-proof
;; and-atom-to-left-proof and-atom-to-right-proof
;; atoms-to-and-atom-proof dec-cases-proof moved here, because they
;; need truth-aconst .

;; We prove "(boole1 -> boole2) -> boole1 impb boole2" from cases axioms

;; "all boole2((T -> boole2) -> True impb boole2) ->
;;  all boole2((F -> boole2) -> False impb boole2) ->
;;  all boole10,boole2((boole10 -> boole2) -> boole10 impb boole2)"

(define imp-to-atom-proof
  (let ((var1 (type-to-new-var (py "boole")))
        (var2 (type-to-new-var (py "boole")))
        (var3 (type-to-new-var (py "boole"))))
    (make-proof-in-all-intro-form
     var1
     (mk-proof-in-elim-form
      (make-proof-in-aconst-form
       (all-formula-to-cases-aconst
        (pf
	 "all boole1,boole2((boole1 -> boole2) -> ImpConst boole1 boole2)")))
      (make-term-in-var-form var1)
      (make-proof-in-all-intro-form
       var2
       (mk-proof-in-elim-form
        (make-proof-in-aconst-form
         (all-formula-to-cases-aconst
          (pf "all boole2((T -> boole2) -> ImpConst True boole2)")))
        (make-term-in-var-form var2)
        (mk-proof-in-intro-form
         (formula-to-new-avar (pf "T -> T"))
         (make-proof-in-aconst-form truth-aconst))
        (let ((u (formula-to-new-avar (pf "T -> F"))))
          (mk-proof-in-intro-form
           u (make-proof-in-imp-elim-form
              (make-proof-in-avar-form u)
              (make-proof-in-aconst-form truth-aconst))))))
      (make-proof-in-all-intro-form
       var3
       (mk-proof-in-elim-form
	(make-proof-in-aconst-form
	 (all-formula-to-cases-aconst
	  (pf "all boole2((F -> boole2) -> ImpConst False boole2)")))
	(make-term-in-var-form var3)
	(mk-proof-in-intro-form
	 (formula-to-new-avar (pf "F -> T"))
	 (make-proof-in-aconst-form truth-aconst))
	(mk-proof-in-intro-form
	 (formula-to-new-avar (pf "F -> F"))
	 (make-proof-in-aconst-form truth-aconst))))))))

(define atom-to-imp-proof
  (let ((var1 (pv "boole1"))
        (var2 (pv "boole2")))
    (mk-proof-in-intro-form
     var1
     (mk-proof-in-elim-form
      (make-proof-in-aconst-form
       (all-formula-to-cases-aconst
        (pf "all boole1,boole2(ImpConst boole1 boole2 -> boole1 -> boole2)")))
      (make-term-in-var-form var1)
      (mk-proof-in-intro-form
       var2
       (mk-proof-in-elim-form
        (make-proof-in-aconst-form
         (all-formula-to-cases-aconst
          (pf "all boole2(ImpConst True boole2 -> T -> boole2)")))
        (make-term-in-var-form var2)
        (mk-proof-in-intro-form
         (formula-to-new-avar (pf "T"))
         (formula-to-new-avar (pf "T"))
         (make-proof-in-aconst-form truth-aconst))
        (let ((u (formula-to-new-avar (pf "F"))))
          (mk-proof-in-intro-form
           u (formula-to-new-avar (pf "T"))
           (make-proof-in-avar-form u)))))
      (mk-proof-in-intro-form
       var2
       (mk-proof-in-elim-form
        (make-proof-in-aconst-form
         (all-formula-to-cases-aconst
          (pf "all boole2(ImpConst False boole2 -> F -> boole2)")))
        (make-term-in-var-form var2)
        (mk-proof-in-intro-form
         (formula-to-new-avar (pf "T"))
	 (formula-to-new-avar (pf "F"))
	 (make-proof-in-aconst-form truth-aconst))
	(let ((u (formula-to-new-avar (pf "F"))))
	  (mk-proof-in-intro-form
	   (formula-to-new-avar (pf "T")) u
	   (make-proof-in-avar-form u)))))))))

(define and-atom-to-left-proof
  (mk-proof-in-intro-form
   (pv "boole1")
   (mk-proof-in-elim-form
    (make-proof-in-aconst-form
     (all-formula-to-cases-aconst
      (pf "all boole1,boole2(AndConst boole1 boole2 -> boole1)")))
    (pt "boole1")
    (mk-proof-in-intro-form
     (pv "boole2")
     (formula-to-new-avar (pf "boole2"))
     (make-proof-in-aconst-form truth-aconst))
    (let ((u (formula-to-new-avar (pf "F"))))
      (mk-proof-in-intro-form
       (pv "boole2") u (make-proof-in-avar-form u))))))

(define and-atom-to-right-proof
  (let ((var1 (pv "boole1"))
        (var2 (pv "boole2")))
    (mk-proof-in-intro-form
     var1
     var2
     (mk-proof-in-elim-form
      (make-proof-in-aconst-form
       (all-formula-to-cases-aconst
	(pf "all boole2(AndConst boole1 boole2 -> boole2)")))
      (make-term-in-var-form var1)
      (make-term-in-var-form var2)
      (mk-proof-in-intro-form
       (formula-to-new-avar (pf "AndConst boole1 True"))
       (make-proof-in-aconst-form truth-aconst))
      (mk-proof-in-elim-form
       (make-proof-in-aconst-form
	(all-formula-to-cases-aconst
	 (pf "all boole1(AndConst boole1 False -> F)")))
       (make-term-in-var-form var1)
       (let ((u (formula-to-new-avar (pf "F"))))
	 (mk-proof-in-intro-form u (make-proof-in-avar-form u)))
       (let ((u (formula-to-new-avar (pf "F"))))
	 (mk-proof-in-intro-form u (make-proof-in-avar-form u))))))))

(define atoms-to-and-atom-proof
  (let ((var1 (pv "boole1"))
        (var2 (pv "boole2")))
    (mk-proof-in-intro-form
     var1
     (mk-proof-in-elim-form
      (make-proof-in-aconst-form
       (all-formula-to-cases-aconst
        (pf "all boole1,boole2(boole1 -> boole2 -> AndConst boole1 boole2)")))
      (make-term-in-var-form var1)
      (mk-proof-in-intro-form
       var2
       (mk-proof-in-elim-form
        (make-proof-in-aconst-form
         (all-formula-to-cases-aconst
          (pf "all boole2(T -> boole2 -> AndConst True boole2)")))
        (make-term-in-var-form var2)
        (mk-proof-in-intro-form
         (formula-to-new-avar (pf "T"))
         (mk-proof-in-intro-form
          (formula-to-new-avar (pf "T"))
          (make-proof-in-aconst-form truth-aconst)))
        (let ((u (formula-to-new-avar (pf "F"))))
          (mk-proof-in-intro-form
           (formula-to-new-avar (pf "T"))
           (mk-proof-in-intro-form
            u (make-proof-in-avar-form u))))))
      (mk-proof-in-intro-form
       var2
       (mk-proof-in-elim-form
        (make-proof-in-aconst-form
         (all-formula-to-cases-aconst
          (pf "all boole2(F -> boole2 -> AndConst False boole2)")))
        (make-term-in-var-form var2)
        (let ((u (formula-to-new-avar (pf "F"))))
          (mk-proof-in-intro-form
           u (mk-proof-in-intro-form
              (formula-to-new-avar (pf "T"))
              (make-proof-in-avar-form u))))
        (let ((u (formula-to-new-avar (pf "F"))))
          (mk-proof-in-intro-form
           u (mk-proof-in-intro-form
              (formula-to-new-avar (pf "F"))
              (make-proof-in-avar-form u))))))))))

(define dec-cases-proof
  (let ((var (pv "boole")))
    (mk-proof-in-intro-form
     var
     (mk-proof-in-elim-form
      (make-proof-in-aconst-form
       (all-formula-to-cases-aconst
        (pf "all boole((boole -> (Pvar boole)True) ->
                    ((boole -> F) -> (Pvar boole)False) ->
                    (Pvar boole)boole)")))
      (make-term-in-var-form var)
      (let ((u1 (formula-to-new-avar
                 (pf "T -> (Pvar boole)True") DEFAULT-AVAR-NAME))
            (u2 (formula-to-new-avar
                 (pf "(T -> F) -> (Pvar boole)False")
                 DEFAULT-AVAR-NAME)))
        (mk-proof-in-intro-form
         u1 u2
         (mk-proof-in-elim-form
          (make-proof-in-avar-form u1)
          (make-proof-in-aconst-form truth-aconst))))
      (let ((u1 (formula-to-new-avar
                 (pf "F -> (Pvar boole)True") DEFAULT-AVAR-NAME))
            (u2 (formula-to-new-avar
                 (pf "(F -> F) -> (Pvar boole)False")
                 DEFAULT-AVAR-NAME))
            (u3 (formula-to-new-avar (pf "F") DEFAULT-AVAR-NAME)))
        (mk-proof-in-intro-form
         u1 u2
         (mk-proof-in-elim-form
          (make-proof-in-avar-form u2)
          (make-proof-in-imp-intro-form
           u3 (make-proof-in-avar-form u3)))))))))

;; We initially supply the Cases Lemma If: all boole((boole -> Pvar) ->
;; ((boole -> F) -> Pvar) -> Pvar).  This can be done only here,
;; because for add-theorem we need formula-to-et-type and
;; proof-to-extracted-term .

(define (formula-to-if-proof formula)
  (let* ((var (type-to-new-var (make-alg "boole")))
	 (varterm (make-term-in-var-form var))
	 (varatom (make-atomic-formula varterm))
	 (imp1 (make-imp varatom formula))
	 (imp2 (make-imp (make-imp varatom falsity) formula))
	 (if-kernel (mk-imp imp1 imp2 formula))
	 (all-formula (make-all var if-kernel)))
    (make-proof-in-all-intro-form
     var
     (apply
      mk-proof-in-elim-form
      (append
       (list (make-proof-in-aconst-form
	      (all-formula-to-cases-aconst all-formula)))
       (map make-term-in-var-form (formula-to-free formula))
       (list
	(make-term-in-var-form var)
	(let ((u1 (formula-to-new-avar
		   (make-imp truth formula) DEFAULT-AVAR-NAME))
	      (u2 (formula-to-new-avar
		   (make-imp (make-imp truth falsity) formula)
		   DEFAULT-AVAR-NAME)))
	  (mk-proof-in-intro-form
	   u1 u2
	   (mk-proof-in-elim-form
	    (make-proof-in-avar-form u1)
	    (make-proof-in-aconst-form truth-aconst))))
	(let ((u1 (formula-to-new-avar
		   (make-imp falsity formula) DEFAULT-AVAR-NAME))
	      (u2 (formula-to-new-avar
		   (make-imp (make-imp falsity falsity) formula)
		   DEFAULT-AVAR-NAME))
	      (u3 (formula-to-new-avar falsity DEFAULT-AVAR-NAME)))
	  (mk-proof-in-intro-form
	   u1 u2
	   (mk-proof-in-elim-form
	    (make-proof-in-avar-form u2)
	    (make-proof-in-imp-intro-form
	     u3 (make-proof-in-avar-form u3)))))))))))

(add-theorem "If" (formula-to-if-proof (pf "Pvar")))

;; If: all boole((boole -> Pvar) -> ((boole -> F) -> Pvar) -> Pvar) can
;; be used for case distinctions.  After animation of cIf we have added
;; the computation rule (cIf alpha4) ->
;; [boole0,alpha4_1,alpha4_2][if boole0 alpha4_1 alpha4_2]

;; (animate "If")

;; We need to define eqd-compat-proof in order to put "EqDCompat" into
;; THEOREMS when loading init.  This can be done only here, because for
;; add-theorem we need formula-to-et-type.

(define eqd-compat-proof
  (let* ((tvar (make-tvar -1 DEFAULT-TVAR-NAME))
	 (name (default-var-name tvar))
	 (var1 (make-var tvar 1 0 name))
	 (var2 (make-var tvar 2 0 name))
	 (varterm1 (make-term-in-var-form var1))
	 (varterm2 (make-term-in-var-form var2))
	 (pvar (make-pvar (make-arity tvar) -1 0 0 ""))
	 (eqd-fla (make-eqd varterm1 varterm2))
	 (fla1 (make-predicate-formula pvar varterm1))
	 (fla2 (make-predicate-formula pvar varterm2))
	 (imp-fla (mk-imp eqd-fla fla1 fla2))
	 (aconst (imp-formulas-to-elim-aconst imp-fla))
	 (u (formula-to-new-avar eqd-fla "u"))
	 (u1 (formula-to-new-avar fla1 "u")))
    (mk-proof-in-nc-intro-form
     var1 var2 (make-proof-in-imp-intro-form
		u (mk-proof-in-elim-form
		   (make-proof-in-aconst-form aconst)
		   varterm1 varterm2
		   (make-proof-in-avar-form u)
		   (make-proof-in-allnc-intro-form
		    var1 (make-proof-in-imp-intro-form
			  u1 (make-proof-in-avar-form u1))))))))

(add-theorem "EqDCompat" eqd-compat-proof)

;; ok, EqDCompat has been added as a new theorem.
;; ok, program constant cEqDCompat: alpha5=>alpha5
;; of t-degree 0 and arity 0 added

;; These messages are to be suppressed (as for "Id" "If")

(define eqd-compat-rev-proof
  (let* ((tvar (make-tvar -1 DEFAULT-TVAR-NAME))
	 (name (default-var-name tvar))
	 (var1 (make-var tvar 1 0 name))
	 (var2 (make-var tvar 2 0 name))
	 (varterm1 (make-term-in-var-form var1))
	 (varterm2 (make-term-in-var-form var2))
	 (pvar (make-pvar (make-arity tvar) -1 0 0 ""))
	 (eqd-fla (make-eqd varterm1 varterm2))
	 (fla1 (make-predicate-formula pvar varterm1))
	 (fla2 (make-predicate-formula pvar varterm2))
	 (imp-fla (mk-imp eqd-fla fla2 fla1))
	 (aconst (imp-formulas-to-elim-aconst imp-fla))
	 (u (formula-to-new-avar eqd-fla "u"))
	 (u2 (formula-to-new-avar fla2 "u")))
    (mk-proof-in-nc-intro-form
     var1 var2 (make-proof-in-imp-intro-form
		u (mk-proof-in-elim-form
		   (make-proof-in-aconst-form aconst)
		   varterm1 varterm2
		   (make-proof-in-avar-form u)
		   (make-proof-in-allnc-intro-form
		    var2 (make-proof-in-imp-intro-form
			  u2 (make-proof-in-avar-form u2))))))))

(add-theorem "EqDCompatRev" eqd-compat-rev-proof)

(define efqeqd-proof
  (let* ((aconst (theorem-name-to-aconst "EqDCompat"))
	 (uninst-formula (aconst-to-uninst-formula aconst))
	 (tvar (var-to-type (allnc-form-to-var uninst-formula)))
	 (final-conclusion
	  (imp-impnc-all-allnc-form-to-final-conclusion uninst-formula))
	 (pvar (predicate-form-to-predicate final-conclusion))
	 (vars (all-allnc-form-to-vars uninst-formula))
	 (var1 (car vars))
	 (var2 (cadr vars))
	 (varterm1 (make-term-in-var-form var1))
	 (varterm2 (make-term-in-var-form var2))
	 (boolevar (make-var (py "boole") -1 t-deg-zero ""))
	 (boolevarterm (make-term-in-var-form boolevar))
	 (if-term (make-term-in-if-form
		   boolevarterm (list varterm1 varterm2)))
	 (cterm (make-cterm boolevar (make-eqd if-term varterm2)))
	 (tsubst (make-subst tvar (py "boole")))
	 (psubst (make-subst-wrt pvar-cterm-equal? pvar cterm))
	 (inst-aconst (make-aconst (aconst-to-name aconst) ;"EqDCompat"
				   (aconst-to-kind aconst) ;'theorem
				   uninst-formula
				   (append tsubst psubst)))
	 (falsity-avar (formula-to-new-avar falsity))
	 (false-eqd-true-proof
	  (mk-proof-in-elim-form
	   (make-proof-in-aconst-form atom-to-eqd-true-aconst)
	   (make-term-in-const-form false-const)
	   (make-proof-in-avar-form falsity-avar)))
	 (idpc (make-idpredconst "EqD" (list tvar) '()))
	 (initeqd-aconst (number-and-idpredconst-to-intro-aconst 0 idpc))
	 (initeqd-proof (mk-proof-in-elim-form
			 (make-proof-in-aconst-form initeqd-aconst)
			 varterm2))
	 (elim-proof (mk-proof-in-elim-form
		      (make-proof-in-aconst-form inst-aconst)
		      varterm1 varterm2
		      (make-term-in-const-form false-const)
		      (make-term-in-const-form true-const)
		      false-eqd-true-proof
		      initeqd-proof))
	 (elim-proof-with-normalized-formula
	  (list 'proof-in-imp-elim-form
		(nf (proof-to-formula elim-proof))
		(proof-in-imp-elim-form-to-op elim-proof)
		(proof-in-imp-elim-form-to-arg elim-proof))))
    (mk-proof-in-intro-form
     falsity-avar var1 var2 elim-proof-with-normalized-formula)))

(add-theorem "EfqEqD" efqeqd-proof)

(define efq-atom-proof
  (let* ((aconst (theorem-name-to-aconst "EfqEqD"))
	 (uninst-formula (aconst-to-uninst-formula aconst))
	 (tvar (var-to-type (all-form-to-var
				    (imp-form-to-conclusion uninst-formula))))
	 (tsubst (make-subst tvar (make-alg "boole")))
	 (subst-aconst (aconst-substitute aconst tsubst))
	 (inst-formula (aconst-to-inst-formula subst-aconst))
	 (var (all-form-to-var (imp-form-to-conclusion inst-formula)))
	 (falsity-avar (formula-to-new-avar falsity))
	 (elim-proof1
	   (mk-proof-in-elim-form
	    (make-proof-in-aconst-form subst-aconst)
	    (make-proof-in-avar-form falsity-avar)
	    (make-term-in-var-form var)
	    (make-term-in-const-form true-const)))
	 (elim-proof2
	   (mk-proof-in-elim-form
	    (make-proof-in-aconst-form eqd-true-to-atom-aconst)
	    (make-term-in-var-form var)
	    elim-proof1)))
    (mk-proof-in-intro-form
     falsity-avar var elim-proof2)))

(add-theorem "EfqAtom" efq-atom-proof)

;; extotal-elim-aconst and extotal-intro-aconst can be added only here,
;; because they need ExR.

(define extotal-intro-aconst
  (let* ((tvar (make-tvar -1 DEFAULT-TVAR-NAME))
	 (name (default-var-name tvar))
	 (var (make-var tvar -1 1 name))
	 (varpartial (make-var tvar -1 t-deg-zero name))
	 (varterm (make-term-in-var-form var))
	 (varpartialterm (make-term-in-var-form varpartial))
	 (pvar (make-pvar (make-arity tvar) -1 h-deg-zero n-deg-zero ""))
	 (ex-fla (mk-ex var (make-predicate-formula pvar varterm)))
	 (expartial-fla
	  (mk-exr varpartial
		  (mk-and (make-total varpartialterm)
			  (make-predicate-formula pvar varpartialterm))))
	 (formula-of-extotal-intro-aconst (mk-imp expartial-fla ex-fla)))
    (make-aconst "ExTotalIntro"
		 'axiom formula-of-extotal-intro-aconst empty-subst)))

;; (pp (aconst-to-formula extotal-intro-aconst))
;; exr alpha^(Total alpha^ & (Pvar alpha)alpha^) -> ex alpha (Pvar alpha)alpha

(define extotal-elim-aconst
  (let* ((tvar (make-tvar -1 DEFAULT-TVAR-NAME))
	 (name (default-var-name tvar))
	 (var (make-var tvar -1 1 name))
	 (varpartial (make-var tvar -1 t-deg-zero name))
	 (varterm (make-term-in-var-form var))
	 (varpartialterm (make-term-in-var-form varpartial))
	 (pvar (make-pvar (make-arity tvar) -1 h-deg-zero n-deg-zero ""))
	 (ex-fla (mk-ex var (make-predicate-formula pvar varterm)))
	 (expartial-fla
	  (mk-exr varpartial
		  (mk-and (make-total varpartialterm)
			  (make-predicate-formula pvar varpartialterm))))
	 (formula-of-extotal-elim-aconst (mk-imp ex-fla expartial-fla)))
    (make-aconst "ExTotalElim"
		 'axiom formula-of-extotal-elim-aconst empty-subst)))

;; (pp (aconst-to-formula extotal-elim-aconst))
;; ex alpha (Pvar alpha)alpha -> exr alpha^(Total alpha^ & (Pvar alpha)alpha^)

(add-theorem "ExTotalIntro" (make-proof-in-aconst-form extotal-intro-aconst))
(add-theorem "ExTotalElim" (make-proof-in-aconst-form extotal-elim-aconst))

(define exdtotal-intro-aconst
  (let* ((tvar (make-tvar -1 DEFAULT-TVAR-NAME))
	 (name (default-var-name tvar))
	 (var (make-var tvar -1 1 name))
	 (varpartial (make-var tvar -1 t-deg-zero name))
	 (varterm (make-term-in-var-form var))
	 (varpartialterm (make-term-in-var-form varpartial))
	 (pvar (make-pvar (make-arity tvar) -1 h-deg-zero n-deg-zero ""))
	 (exd-fla (mk-exd var (make-predicate-formula pvar varterm)))
	 (expartial-fla
	  (mk-exr varpartial
		  (mk-andd (make-total varpartialterm)
			   (make-predicate-formula pvar varpartialterm))))
	 (formula-of-exdtotal-intro-aconst (mk-imp expartial-fla exd-fla)))
    (make-aconst "ExDTotalIntro"
		 'axiom formula-of-exdtotal-intro-aconst empty-subst)))

(add-theorem "ExDTotalIntro" (make-proof-in-aconst-form exdtotal-intro-aconst))

(define exltotal-intro-aconst
  (let* ((tvar (make-tvar -1 DEFAULT-TVAR-NAME))
	 (name (default-var-name tvar))
	 (var (make-var tvar -1 1 name))
	 (varpartial (make-var tvar -1 t-deg-zero name))
	 (varterm (make-term-in-var-form var))
	 (varpartialterm (make-term-in-var-form varpartial))
	 (pvar (make-pvar (make-arity tvar) -1 h-deg-one n-deg-one ""))
	 (exl-fla (mk-exl var (make-predicate-formula pvar varterm)))
	 (expartial-fla
	  (mk-exr varpartial
		  (mk-andl (make-total varpartialterm)
			   (make-predicate-formula pvar varpartialterm))))
	 (formula-of-exltotal-intro-aconst (mk-imp expartial-fla exl-fla)))
    (make-aconst "ExLTotalIntro"
		 'axiom formula-of-exltotal-intro-aconst empty-subst)))

(add-theorem "ExLTotalIntro" (make-proof-in-aconst-form exltotal-intro-aconst))

(define exrtotal-intro-aconst
  (let* ((tvar (make-tvar -1 DEFAULT-TVAR-NAME))
	 (name (default-var-name tvar))
	 (var (make-var tvar -1 1 name))
	 (varpartial (make-var tvar -1 t-deg-zero name))
	 (varterm (make-term-in-var-form var))
	 (varpartialterm (make-term-in-var-form varpartial))
	 (pvar (make-pvar (make-arity tvar) -1 h-deg-zero n-deg-zero ""))
	 (exr-fla (mk-exr var (make-predicate-formula pvar varterm)))
	 (expartial-fla
	  (mk-exr varpartial
		  (mk-andr (make-totalmr varpartialterm varpartialterm)
			   (make-predicate-formula pvar varpartialterm))))
	 (formula-of-exrtotal-intro-aconst (mk-imp expartial-fla exr-fla)))
    (make-aconst "ExRTotalIntro"
		 'axiom formula-of-exrtotal-intro-aconst empty-subst)))

(add-theorem "ExRTotalIntro" (make-proof-in-aconst-form exrtotal-intro-aconst))

(define exutotal-intro-aconst
  (let* ((tvar (make-tvar -1 DEFAULT-TVAR-NAME))
	 (name (default-var-name tvar))
	 (var (make-var tvar -1 1 name))
	 (varpartial (make-var tvar -1 t-deg-zero name))
	 (varterm (make-term-in-var-form var))
	 (varpartialterm (make-term-in-var-form varpartial))
	 (pvar (make-pvar (make-arity tvar) -1 h-deg-zero n-deg-zero ""))
	 (exu-fla (mk-exu var (make-predicate-formula pvar varterm)))
	 (expartial-fla
	  (mk-exu varpartial
		  (mk-andu (make-total varpartialterm)
			   (make-predicate-formula pvar varpartialterm))))
	 (formula-of-exutotal-intro-aconst (mk-imp expartial-fla exu-fla)))
    (make-aconst "ExUTotalIntro"
		 'axiom formula-of-exutotal-intro-aconst empty-subst)))

(add-theorem "ExUTotalIntro" (make-proof-in-aconst-form exutotal-intro-aconst))

;; (pp (aconst-to-formula exdtotal-intro-aconst))
;; (pp (aconst-to-formula exltotal-intro-aconst))
;; (pp (aconst-to-formula exrtotal-intro-aconst))
;; (pp (aconst-to-formula exutotal-intro-aconst))

(define inhabtotal-aconst ;obsolete
  (let ((formula-of-inhab-total-aconst
	 (make-total (make-term-in-const-form
		      (pconst-name-to-pconst "Inhab")))))
    (make-aconst
     "InhabTotal" 'axiom formula-of-inhab-total-aconst empty-subst)))

(add-theorem "InhabTotal" (make-proof-in-aconst-form inhabtotal-aconst))

(define inhabtotalmr-aconst ;obsolete
  (let* ((inhab-term (make-term-in-const-form (pconst-name-to-pconst "Inhab")))
	 (formula-of-inhab-totalmr-aconst
	  (make-totalmr inhab-term inhab-term)))
    (make-aconst
     "InhabTotalMR" 'axiom formula-of-inhab-totalmr-aconst empty-subst)))

(add-theorem "InhabTotalMR" (make-proof-in-aconst-form inhabtotalmr-aconst))

(define and-const-total-proof
  (let* ((bvar1 (make-var (make-alg "boole") 1 0 ""))
	 (bvar2 (make-var (make-alg "boole") 2 0 ""))
	 (bvarterm1 (make-term-in-var-form bvar1))
	 (bvarterm2 (make-term-in-var-form bvar2))
	 (totalb-idpc (make-idpredconst "TotalBoole" '() '()))
	 (totalb-fla1 (make-predicate-formula totalb-idpc bvarterm1))
	 (totalb-fla2 (make-predicate-formula totalb-idpc bvarterm2))
	 (and-term (mk-term-in-app-form
		    (make-term-in-const-form and-const) bvarterm1 bvarterm2))
	 (totalb-and-fla (make-predicate-formula totalb-idpc and-term))
	 (imp-fla (make-imp totalb-fla1 totalb-and-fla))
	 (aconst (imp-formulas-to-elim-aconst imp-fla))
	 (intro-aconst (number-and-idpredconst-to-intro-aconst 1 totalb-idpc))
	 (u1 (formula-to-new-avar totalb-fla1 "u"))
	 (u2 (formula-to-new-avar totalb-fla2 "u")))
    (make-proof-in-allnc-intro-form
     bvar1 (make-proof-in-imp-intro-form
	    u1 (make-proof-in-allnc-intro-form
		bvar2 (make-proof-in-imp-intro-form
		       u2 (mk-proof-in-elim-form
			   (make-proof-in-aconst-form aconst)
			   bvarterm1 bvarterm2
			   (make-proof-in-avar-form u1)
			   (make-proof-in-avar-form u2)
			   (make-proof-in-aconst-form intro-aconst))))))))

(add-theorem "AndConstTotal" and-const-total-proof)

(define imp-const-total-proof
  (let* ((bvar1 (make-var (make-alg "boole") 1 0 ""))
	 (bvar2 (make-var (make-alg "boole") 2 0 ""))
	 (bvarterm1 (make-term-in-var-form bvar1))
	 (bvarterm2 (make-term-in-var-form bvar2))
	 (totalb-idpc (make-idpredconst "TotalBoole" '() '()))
	 (totalb-fla1 (make-predicate-formula totalb-idpc bvarterm1))
	 (totalb-fla2 (make-predicate-formula totalb-idpc bvarterm2))
	 (imp-term (mk-term-in-app-form
		    (make-term-in-const-form imp-const) bvarterm1 bvarterm2))
	 (totalb-imp-fla (make-predicate-formula totalb-idpc imp-term))
	 (imp-fla (make-imp totalb-fla1 (make-imp totalb-fla2 totalb-imp-fla)))
	 (elim-aconst (imp-formulas-to-elim-aconst imp-fla))
	 (u1 (formula-to-new-avar totalb-fla1 "u"))
	 (u2 (formula-to-new-avar totalb-fla2 "u"))
	 (intro-proof1 (make-proof-in-imp-intro-form
			u2 (make-proof-in-avar-form u2)))
	 (intro-proof2 (make-proof-in-imp-intro-form
			u2 (make-proof-in-aconst-form
			    (number-and-idpredconst-to-intro-aconst
			     0 totalb-idpc))))
	 (elim-proof (mk-proof-in-elim-form
		      (make-proof-in-aconst-form elim-aconst)
		      bvarterm1 bvarterm2
		      (make-proof-in-avar-form u1) intro-proof1 intro-proof2)))
    (mk-proof-in-nc-intro-form
     bvar1 (mk-proof-in-intro-form
	    u1 (mk-proof-in-nc-intro-form
		bvar2 elim-proof)))))

(add-theorem "ImpConstTotal" imp-const-total-proof)

(define or-const-total-proof
  (let* ((bvar1 (make-var (make-alg "boole") 1 0 ""))
	 (bvar2 (make-var (make-alg "boole") 2 0 ""))
	 (bvarterm1 (make-term-in-var-form bvar1))
	 (bvarterm2 (make-term-in-var-form bvar2))
	 (totalb-idpc (make-idpredconst "TotalBoole" '() '()))
	 (totalb-fla1 (make-predicate-formula totalb-idpc bvarterm1))
	 (totalb-fla2 (make-predicate-formula totalb-idpc bvarterm2))
	 (or-term (mk-term-in-app-form
		   (make-term-in-const-form or-const) bvarterm1 bvarterm2))
	 (totalb-or-fla (make-predicate-formula totalb-idpc or-term))
	 (imp-fla (make-imp totalb-fla1 (make-imp totalb-fla2 totalb-or-fla)))
	 (elim-aconst (imp-formulas-to-elim-aconst imp-fla))
	 (u1 (formula-to-new-avar totalb-fla1 "u"))
	 (u2 (formula-to-new-avar totalb-fla2 "u"))
	 (intro-proof1 (make-proof-in-imp-intro-form
			u2 (make-proof-in-aconst-form
			    (number-and-idpredconst-to-intro-aconst
			     0 totalb-idpc))))
	 (intro-proof2 (make-proof-in-imp-intro-form
			u2 (make-proof-in-avar-form u2)))
	 (elim-proof (mk-proof-in-elim-form
		      (make-proof-in-aconst-form elim-aconst)
		      bvarterm1 bvarterm2
		      (make-proof-in-avar-form u1) intro-proof1 intro-proof2)))
    (mk-proof-in-nc-intro-form
     bvar1 (mk-proof-in-intro-form
	    u1 (mk-proof-in-nc-intro-form
		bvar2 elim-proof)))))

(add-theorem "OrConstTotal" or-const-total-proof)

(define neg-const-total-proof
  (let* ((bvar (make-var (make-alg "boole") 1 0 ""))
	 (bvarterm (make-term-in-var-form bvar))
	 (totalb-idpc (make-idpredconst "TotalBoole" '() '()))
	 (totalb-fla (make-predicate-formula totalb-idpc bvarterm))
	 (neg-term (mk-term-in-app-form
		    (make-term-in-const-form neg-const) bvarterm))
	 (totalb-neg-fla (make-predicate-formula totalb-idpc neg-term))
	 (imp-fla (make-imp totalb-fla totalb-neg-fla))
	 (elim-aconst (imp-formulas-to-elim-aconst imp-fla))
	 (u1 (formula-to-new-avar totalb-fla "u"))
	 (elim-proof
	  (mk-proof-in-elim-form
	   (make-proof-in-aconst-form elim-aconst)
	   bvarterm
	   (make-proof-in-avar-form u1)
	   (make-proof-in-aconst-form
	    (number-and-idpredconst-to-intro-aconst 1 totalb-idpc))
	   (make-proof-in-aconst-form
	    (number-and-idpredconst-to-intro-aconst 0 totalb-idpc)))))
    (mk-proof-in-nc-intro-form
     bvar (mk-proof-in-intro-form u1 elim-proof))))

(add-theorem "NegConstTotal" neg-const-total-proof)

(define pair-one-total-proof ;of allnc xy^(TotalYprod xy^ -> Total(lft xy^))
  (let* ((tvar1 (make-tvar 1 DEFAULT-TVAR-NAME))
	 (tvar2 (make-tvar 2 DEFAULT-TVAR-NAME))
	 (alg (make-yprod tvar1 tvar2))
	 (idpc (alg-to-totality-idpredconst alg))
	 (var (make-var alg -1 0 ""))
	 (varterm (make-term-in-var-form var))
	 (prem (make-predicate-formula idpc varterm))
	 (pconst (pconst-name-to-pconst "PairOne"))
	 (pconst-term (make-term-in-const-form pconst))
	 (appterm (make-term-in-app-form pconst-term varterm))
	 (concl (make-total appterm))
	 (imp-formula (make-imp prem concl))
	 (elim-aconst (imp-formulas-to-elim-aconst imp-formula))
	 (var1 (make-var tvar1 1 0 ""))
	 (var2 (make-var tvar2 2 0 ""))
	 (varterm1 (make-term-in-var-form var1))
	 (varterm2 (make-term-in-var-form var2))
	 (u1 (formula-to-new-avar (make-total varterm1)))
	 (u2 (formula-to-new-avar (make-total varterm2)))
	 (clause-proof (mk-proof-in-nc-intro-form
			var1 var2 (mk-proof-in-intro-form
				   u1 u2 (make-proof-in-avar-form u1))))
	 (u (formula-to-new-avar prem))
	 (elim-proof
	  (mk-proof-in-elim-form
	   (make-proof-in-aconst-form elim-aconst)
	   varterm (make-proof-in-avar-form u) clause-proof)))
    (mk-proof-in-nc-intro-form
     var (mk-proof-in-intro-form u elim-proof))))

(add-theorem "PairOneTotal" pair-one-total-proof)

(define pair-two-total-proof ;of allnc xy^(TotalYprod xy^ -> Total(rht xy^))
  (let* ((tvar1 (make-tvar 1 DEFAULT-TVAR-NAME))
	 (tvar2 (make-tvar 2 DEFAULT-TVAR-NAME))
	 (alg (make-yprod tvar1 tvar2))
	 (idpc (alg-to-totality-idpredconst alg))
	 (var (make-var alg -1 0 ""))
	 (varterm (make-term-in-var-form var))
	 (prem (make-predicate-formula idpc varterm))
	 (pconst (pconst-name-to-pconst "PairTwo"))
	 (pconst-term (make-term-in-const-form pconst))
	 (appterm (make-term-in-app-form pconst-term varterm))
	 (concl (make-total appterm))
	 (imp-formula (make-imp prem concl))
	 (elim-aconst (imp-formulas-to-elim-aconst imp-formula))
	 (var1 (make-var tvar1 1 0 ""))
	 (var2 (make-var tvar2 2 0 ""))
	 (varterm1 (make-term-in-var-form var1))
	 (varterm2 (make-term-in-var-form var2))
	 (u1 (formula-to-new-avar (make-total varterm1)))
	 (u2 (formula-to-new-avar (make-total varterm2)))
	 (clause-proof (mk-proof-in-nc-intro-form
			var1 var2 (mk-proof-in-intro-form
				   u1 u2 (make-proof-in-avar-form u2))))
	 (u (formula-to-new-avar prem))
	 (elim-proof
	  (mk-proof-in-elim-form
	   (make-proof-in-aconst-form elim-aconst)
	   varterm (make-proof-in-avar-form u) clause-proof)))
    (mk-proof-in-nc-intro-form
     var (mk-proof-in-intro-form u elim-proof))))

(add-theorem "PairTwoTotal" pair-two-total-proof)

(define boole-if-total-proof
  (let* ((bvar (make-var (make-alg "boole") -1 0 ""))
	 (bvarterm (make-term-in-var-form bvar))
	 (totalb-idpc (make-idpredconst "TotalBoole" '() '()))
	 (totalb-fla (make-predicate-formula totalb-idpc bvarterm))
	 (tvar (make-tvar -1 DEFAULT-TVAR-NAME))
	 (name (default-var-name tvar))
	 (var1 (make-var tvar 1 0 name))
	 (var2 (make-var tvar 2 0 name))
	 (varterm1 (make-term-in-var-form var1))
	 (varterm2 (make-term-in-var-form var2))
	 (total-fla1 (make-total varterm1))
	 (total-fla2 (make-total varterm2))
	 (if-term (make-term-in-if-form bvarterm (list varterm1 varterm2)))
	 (imp-fla (make-imp totalb-fla (make-total if-term)))
	 (aconst (imp-formulas-to-elim-aconst imp-fla))
	 (u (formula-to-new-avar totalb-fla "u"))
	 (u1 (formula-to-new-avar total-fla1 "u"))
	 (u2 (formula-to-new-avar total-fla2 "u")))
    (make-proof-in-allnc-intro-form
     bvar (make-proof-in-imp-intro-form
	   u (mk-proof-in-nc-intro-form
	      var1 var2 (mk-proof-in-intro-form
			 u1 u2 (mk-proof-in-elim-form
				(make-proof-in-aconst-form aconst)
				bvarterm varterm1 varterm2
				(make-proof-in-avar-form u)
				(make-proof-in-avar-form u1)
				(make-proof-in-avar-form u2))))))))

(add-theorem "BooleIfTotal" boole-if-total-proof)

(define boole-eq-total-proof
  (let* ((bvar1 (make-var (make-alg "boole") 1 0 ""))
	 (bvarterm1 (make-term-in-var-form bvar1))
	 (totalb-idpc (make-idpredconst "TotalBoole" '() '()))
	 (totalb-fla1 (make-predicate-formula totalb-idpc bvarterm1))
	 (bvar2 (make-var (make-alg "boole") 2 0 ""))
	 (bvarterm2 (make-term-in-var-form bvar2))
	 (totalb-idpc (make-idpredconst "TotalBoole" '() '()))
	 (totalb-fla2 (make-predicate-formula totalb-idpc bvarterm2))
	 (eq-term (make-=-term bvarterm1 bvarterm2))
	 (totaleq-fla (make-predicate-formula totalb-idpc eq-term))
	 (eq-term-true (make-=-term (make-term-in-const-form true-const)
				    bvarterm2))
	 (totaleq-fla-true (make-predicate-formula totalb-idpc eq-term-true))
	 (eq-term-false (make-=-term (make-term-in-const-form false-const)
				    bvarterm2))
	 (totaleq-fla-false (make-predicate-formula totalb-idpc eq-term-false))
	 (imp-fla (make-imp totalb-fla1
			    (make-allnc
			     bvar2 (make-imp totalb-fla2 totaleq-fla))))
	 (aconst (imp-formulas-to-elim-aconst imp-fla))
	 (imp-fla-true (make-imp totalb-fla2 totaleq-fla-true))
	 (aconst-true (imp-formulas-to-elim-aconst imp-fla-true))
	 (imp-fla-false (make-imp totalb-fla2 totaleq-fla-false))
	 (aconst-false (imp-formulas-to-elim-aconst imp-fla-false))
	 (intro-aconst-true
	  (number-and-idpredconst-to-intro-aconst 0 totalb-idpc))
	 (intro-aconst-false
	  (number-and-idpredconst-to-intro-aconst 1 totalb-idpc))
	 (u1 (formula-to-new-avar totalb-fla1))
	 (u2 (formula-to-new-avar totalb-fla2))
	 (proof-true
	  (make-proof-in-allnc-intro-form
	   bvar2 (make-proof-in-imp-intro-form
		  u2 (mk-proof-in-elim-form
		      (make-proof-in-aconst-form aconst-true)
		      bvarterm2 (make-proof-in-avar-form u2)
		      (make-proof-in-aconst-form intro-aconst-true)
		      (make-proof-in-aconst-form intro-aconst-false)))))
	 (proof-false
	  (make-proof-in-allnc-intro-form
	   bvar2 (make-proof-in-imp-intro-form
		  u2 (mk-proof-in-elim-form
		      (make-proof-in-aconst-form aconst-false)
		      bvarterm2 (make-proof-in-avar-form u2)
		      (make-proof-in-aconst-form intro-aconst-false)
		      (make-proof-in-aconst-form intro-aconst-true))))))
    (make-proof-in-allnc-intro-form
     bvar1 (make-proof-in-imp-intro-form
	    u1 (mk-proof-in-elim-form
		(make-proof-in-aconst-form aconst)
		bvarterm1 (make-proof-in-avar-form u1)
		proof-true proof-false)))))

(add-theorem "BooleEqTotal" boole-eq-total-proof)

(define boole-total-var-proof
  (let* ((boolevar (make-var (make-alg "boole") -1 t-deg-zero ""))
	 (total-boole-formula
	  (make-predicate-formula
	   (make-idpredconst "TotalBoole" '() '())
	   (make-term-in-var-form boolevar)))
	 (avar (make-avar total-boole-formula -1 "u")))
    (mk-proof-in-elim-form
     (make-proof-in-aconst-form
      (aconst-substitute
       alltotal-intro-aconst
       (append
	(make-subst (make-tvar -1 "alpha") (make-alg "boole"))
	(make-subst
	 (make-pvar (make-arity '(tvar -1 "alpha")) -1 h-deg-zero n-deg-zero "")
	 (make-cterm boolevar total-boole-formula)))))
     (make-proof-in-allnc-intro-form
      boolevar (make-proof-in-imp-intro-form
		avar (make-proof-in-avar-form avar))))))

(add-theorem "BooleTotalVar" boole-total-var-proof)

(define yprod-total-var-proof
  (let* ((yprodvar
	  (make-var
	   (make-alg "yprod" (make-tvar 1 "alpha") (make-tvar 2 "alpha"))
	   -1 t-deg-zero ""))
	 (total-yprod-formula
	  (make-predicate-formula
	   (make-idpredconst
	    "TotalYprod" (list (make-tvar 1 "alpha") (make-tvar 2 "alpha")) '())
	   (make-term-in-var-form yprodvar)))
	 (avar (make-avar total-yprod-formula -1 "u")))
    (mk-proof-in-elim-form
     (make-proof-in-aconst-form
      (aconst-substitute
       alltotal-intro-aconst
       (append
	(make-subst
	 (make-tvar -1 "alpha")
	 (make-alg "yprod" (make-tvar 1 "alpha") (make-tvar 2 "alpha")))
	(make-subst
	 (make-pvar (make-arity '(tvar -1 "alpha")) -1 h-deg-zero n-deg-zero "")
	 (make-cterm yprodvar total-yprod-formula)))))
     (make-proof-in-allnc-intro-form
      yprodvar (make-proof-in-imp-intro-form
		avar (make-proof-in-avar-form avar))))))

(add-theorem "YprodTotalVar" yprod-total-var-proof)

(define ysum-total-var-proof
  (let* ((ysumvar
	  (make-var
	   (make-alg "ysum" (make-tvar 1 "alpha") (make-tvar 2 "alpha"))
	   -1 t-deg-zero ""))
	 (total-ysum-formula
	  (make-predicate-formula
	   (make-idpredconst
	    "TotalYsum" (list (make-tvar 1 "alpha") (make-tvar 2 "alpha")) '())
	   (make-term-in-var-form ysumvar)))
	 (avar (make-avar total-ysum-formula -1 "u")))
    (mk-proof-in-elim-form
     (make-proof-in-aconst-form
      (aconst-substitute
       alltotal-intro-aconst
       (append
	(make-subst
	 (make-tvar -1 "alpha")
	 (make-alg "ysum" (make-tvar 1 "alpha") (make-tvar 2 "alpha")))
	(make-subst
	 (make-pvar (make-arity '(tvar -1 "alpha")) -1 h-deg-zero n-deg-zero "")
	 (make-cterm ysumvar total-ysum-formula)))))
     (make-proof-in-allnc-intro-form
      ysumvar (make-proof-in-imp-intro-form
		avar (make-proof-in-avar-form avar))))))

(add-theorem "YsumTotalVar" ysum-total-var-proof)

;; For invariance axioms we need aconsts invarex-aconst invarall-aconst.

;; PVAR-TO-MR-PVAR-ALIST initially has
;; (Pvar alpha) -> (Pvar gamma alpha)^
;; Pvar2 -> (Pvar beta2)^2
;; Pvar1 -> (Pvar beta1)^1
;; Pvar  -> (Pvar beta)^

(define PVAR-TO-MR-PVAR-ALIST
  (list
   (list (make-pvar (make-arity (make-tvar -1 "alpha"))
		    -1 h-deg-zero n-deg-zero "")
	 (make-pvar (make-arity (make-tvar -1 "gamma") (make-tvar -1 "alpha"))
		    -1 h-deg-one n-deg-zero ""))
   (list (make-pvar (make-arity)
		    2 h-deg-zero n-deg-zero "")
	 (make-pvar (make-arity (make-tvar 2 "beta"))
		    2 h-deg-one n-deg-zero ""))
   (list (make-pvar (make-arity)
		    1 h-deg-zero n-deg-zero "")
	 (make-pvar (make-arity (make-tvar 1 "beta"))
		    1 h-deg-one n-deg-zero ""))
   (list (make-pvar (make-arity)
		    -1 h-deg-zero n-deg-zero "")
	 (make-pvar (make-arity (make-tvar -1 "beta"))
		    -1 h-deg-one n-deg-zero ""))))

(define (PVAR-TO-MR-PVAR pvar)
  (let ((info (assoc pvar PVAR-TO-MR-PVAR-ALIST)))
    (if info
	(cadr info)
	(let* ((type (PVAR-TO-TVAR pvar))
	       (arity (pvar-to-arity pvar))
	       (types (arity-to-types arity))
	       (newarity (apply make-arity type types))
	       (newpvar (arity-to-new-harrop-pvar newarity)))
	      (set! PVAR-TO-MR-PVAR-ALIST
		    (cons (list pvar newpvar) PVAR-TO-MR-PVAR-ALIST))
	      newpvar))))

;; We will also need
(add-mr-ids "ExD")
(add-mr-ids "ExL")
(add-mr-ids "ExR")
(add-mr-ids "ExDT")
(add-mr-ids "ExLT")
(add-mr-ids "ExRT")
(add-mr-ids "AndD")
(add-mr-ids "AndL")
(add-mr-ids "AndR")
(add-mr-ids "OrD")
(add-mr-ids "OrL")
(add-mr-ids "OrR")
(add-mr-ids "OrU")
(add-mr-ids "ExPT")

(define invarex-aconst
  (let* ((pvar (make-pvar (make-arity) -1 h-deg-zero n-deg-zero ""))
	 (mr-pvar (PVAR-TO-MR-PVAR pvar))
	 (pvar-fla (make-predicate-formula pvar))
	 (tvar (PVAR-TO-TVAR pvar))
	 (var (type-to-new-partial-var tvar))
	 (varterm (make-term-in-var-form var))
	 (real-fla (real-and-formula-to-mr-formula varterm pvar-fla))
	 (exl-fla (rename-variables (make-exl var real-fla))))
    (make-aconst "InvarEx" 'axiom (make-imp pvar-fla exl-fla) empty-subst)))

(add-theorem "InvarEx" (make-proof-in-aconst-form invarex-aconst))

(define invarall-aconst
  (let* ((pvar (make-pvar (make-arity) -1 h-deg-zero n-deg-zero ""))
	 (mr-pvar (PVAR-TO-MR-PVAR pvar))
	 (pvar-fla (make-predicate-formula pvar))
	 (tvar (PVAR-TO-TVAR pvar))
	 (var (type-to-new-partial-var tvar))
	 (varterm (make-term-in-var-form var))
	 (real-fla (real-and-formula-to-mr-formula varterm pvar-fla)))
    (make-aconst
     "InvarAll" 'axiom
     (make-all var (make-imp real-fla pvar-fla)) empty-subst)))

(add-theorem "InvarAll" (make-proof-in-aconst-form invarall-aconst))

(define (formula-to-invarex-aconst formula)
  (let* ((uninst-fla (aconst-to-uninst-formula invarex-aconst))
	 (uninst-pvar-fla (imp-form-to-premise uninst-fla))
	 (uninst-exl-fla (imp-form-to-conclusion uninst-fla))
	 (uninst-pvar (predicate-form-to-predicate uninst-pvar-fla))
	 (uninst-var (exl-form-to-var uninst-exl-fla))
	 (tvar (var-to-type uninst-var))
	 (uninst-mr-fla (exl-form-to-kernel uninst-exl-fla))
	 (uninst-mr-pvar (predicate-form-to-predicate uninst-mr-fla))
	 (uninst-varterm (make-term-in-var-form uninst-var))
	 (type (if (not (formula-of-nulltype? formula))
		   (formula-to-et-type formula)
		   (myerror "formula-to-invarex-aconst"
			    "c.r. formula expected" formula)))
	 (tsubst (make-subst tvar type))
	 (cterm (make-cterm formula))
	 (var (type-to-new-partial-var type))
	 (varterm (make-term-in-var-form var))
	 (mr-fla (real-and-formula-to-mr-formula varterm formula))
	 (mr-cterm (make-cterm var mr-fla))
	 (psubst (make-substitution (list uninst-pvar uninst-mr-pvar)
				    (list cterm mr-cterm)))
	 (tpsubst (append tsubst psubst)))
    (aconst-substitute invarex-aconst tpsubst)))

(define (formula-to-invarall-aconst formula)
  (let* ((uninst-fla (aconst-to-uninst-formula invarall-aconst))
	 (uninst-var (all-form-to-var uninst-fla))
	 (uninst-imp-fla (all-form-to-kernel uninst-fla))
	 (uninst-mr-fla (imp-form-to-premise uninst-imp-fla))
	 (uninst-mr-pvar (predicate-form-to-predicate uninst-mr-fla))
	 (uninst-pvar-fla (imp-form-to-conclusion uninst-imp-fla))
	 (uninst-pvar (predicate-form-to-predicate uninst-pvar-fla))
	 (tvar (var-to-type uninst-var))
	 (uninst-varterm (make-term-in-var-form uninst-var))
	 (type (if (not (formula-of-nulltype? formula))
		   (formula-to-et-type formula)
		   (myerror "formula-to-invarall-aconst"
			    "c.r. formula expected" formula)))
	 (tsubst (make-subst tvar type))
	 (cterm (make-cterm formula))
	 (var (type-to-new-partial-var type))
	 (varterm (make-term-in-var-form var))
	 (mr-fla (real-and-formula-to-mr-formula varterm formula))
	 (mr-cterm (make-cterm var mr-fla))
	 (psubst (make-substitution (list uninst-pvar uninst-mr-pvar)
				    (list cterm mr-cterm)))
	 (tpsubst (append tsubst psubst)))
    (aconst-substitute invarall-aconst tpsubst)))

;; (define formula (pf "exl boole2 boole1 eqd boole2"))
;; (pp (aconst-to-formula (formula-to-invarex-aconst formula)))
;; (pp (aconst-to-formula (formula-to-invarall-aconst formula)))

(define totalmrtoeq-aconst
  (let* ((var1 (make-var (make-tvar -1 DEFAULT-TVAR-NAME) 1 t-deg-zero ""))
	 (var (make-var (make-tvar -1 DEFAULT-TVAR-NAME) -1 t-deg-zero ""))
	 (varterm1 (make-term-in-var-form var1))	 
	 (varterm (make-term-in-var-form var))
	 (tmr-predconst
	  (make-predconst (make-arity (make-tvar -1 DEFAULT-TVAR-NAME)
				      (make-tvar -1 DEFAULT-TVAR-NAME))
			  empty-subst -1 "TotalMR"))
	 (tmr-fla (make-predicate-formula tmr-predconst varterm1 varterm))
	 (eqd-fla (make-eqd varterm1 varterm)))
    (make-aconst
     "TotalMRToEq"
     'axiom (mk-all var1 var (make-imp tmr-fla eqd-fla)) empty-subst)))

(add-theorem "TotalMRToEq" (make-proof-in-aconst-form totalmrtoeq-aconst))

;; TotalMRIntro
(set-goal "all alpha TotalMR alpha alpha")
(use "AllTotalIntro")
(assume "alpha^" "Talpha")
(assert "exl alpha^1 TotalMR alpha^1 alpha^")
 (use "InvarEx" (make-cterm (pf "Total alpha^")))
 (use "Talpha")
(assume "ExHyp")
(by-assume "ExHyp" "alpha^1" "alpha1Prop")
(assert "alpha^1 eqd alpha^")
 (use "TotalMRToEq")
 (use "alpha1Prop")
(assume "alpha^1 eqd alpha^")
(simphyp-with-to "alpha1Prop" "alpha^1 eqd alpha^" "alpha1PropInst")
(use "alpha1PropInst")
;; Proof finished.
(save "TotalMRIntro")

;; TotalMRToTotal
(set-goal "all alpha^ allnc alpha^1(TotalMR alpha^1 alpha^ -> Total alpha^)")
(assume "alpha^" "alpha^1" "TMRHyp")
(use-with "InvarAll"
	  (py "alpha")
	  (make-cterm (pv "alpha^") (pf "TotalMR alpha^1 alpha^"))
	  (make-cterm (pf "Total alpha^"))
	  (pt "alpha^")
	  "TMRHyp")
;; Proof finished.
(save "TotalMRToTotal")

(set! COMMENT-FLAG #t)

;; We now aim at giving an internal proof of soundness.

;; make-pvar-to-mr-pvar returns a procedure associating to pvar an
;; mr-pvar with an additional realizer argument.  Usually the type of
;; this argument will be the tvar associated by PVAR-TO-TVAR to pvar.
;; However the idpc-pvar used locally in the stored clauses of an
;; idpredconst needs an mr-pvar where the realizer argument can have a
;; constructor type.  Therefore we have an optional type argument.

(define (make-pvar-to-mr-pvar)
  (let ((assoc-list '()))
    (lambda (pvar . opt-type)
      (let ((info (assoc pvar assoc-list)))
	(if info
	    (cadr info)
	    (let* ((type (if (null? opt-type)
			     (PVAR-TO-TVAR pvar)
			     (car opt-type)))
		   (arity (pvar-to-arity pvar))
		   (types (arity-to-types arity))
		   (newarity (apply make-arity type types))
		   (newpvar (arity-to-new-harrop-pvar newarity)))
	      (set! assoc-list (cons (list pvar newpvar) assoc-list))
	      newpvar))))))

(define (idpredconst-to-mr-idpredconst idpc)
  (let* ((idpc-name (idpredconst-to-name idpc))
	 (types (idpredconst-to-types idpc))
	 (cterms (idpredconst-to-cterms idpc))
	 (mr-idpc-name (string-append idpc-name "MR"))
	 (tsubst (idpredconst-name-and-types-to-tsubst idpc-name types))
	 (idpc-names (idpredconst-name-to-simidpc-names idpc-name))
	 (clauses (apply append (map idpredconst-name-to-clauses idpc-names)))
	 (clause-et-types (map formula-to-et-type clauses))
	 (clause-et-tvars (apply union (map type-to-tvars clause-et-types)))
	 (param-pvars (idpredconst-name-to-param-pvars idpc-name))
	 (et-tvars-of-param-pvars (map PVAR-TO-TVAR param-pvars))
	 (mr-et-tvars (list-transform-positive clause-et-tvars
			(lambda (tvar) (member tvar et-tvars-of-param-pvars))))
	 (pvar-et-type-alist
	  (map (lambda (pvar cterm)
		 (let ((formula (cterm-to-formula cterm)))
		   (list pvar (if (formula-of-nulltype? formula)
				  (make-alg "unit")
				  (formula-to-et-type formula)))))
	       param-pvars cterms))
	 (relevant-pvar-et-type-alist
	  (list-transform-positive pvar-et-type-alist
	    (lambda (x) (member (PVAR-TO-TVAR (car x)) mr-et-tvars))))
	 (et-tsubst (map (lambda (x)
			   (let ((pvar (car x))
				 (et-type (cadr x)))
			     (list (PVAR-TO-TVAR pvar) et-type)))
			 relevant-pvar-et-type-alist))
	 (orig-and-mr-tvars (idpredconst-name-to-tvars mr-idpc-name))
	 (orig-and-mr-types (map (lambda (tvar)
				   (let ((info1 (assoc tvar tsubst))
					 (info2 (assoc tvar et-tsubst)))
				     (cond (info1 (cadr info1))
					   (info2 (cadr info2))
					   (else tvar))))
				 orig-and-mr-tvars))
	 (orig-and-mr-pvars (idpredconst-name-to-param-pvars mr-idpc-name))
	 (pvar-cterm-alist (map list param-pvars cterms)) ;not a psubst
	 (mr-pvar-cterm-alist
	  (map (lambda (pvar cterm)
		 (let ((vars (cterm-to-vars cterm))
		       (formula (cterm-to-formula cterm)))
		   (if ;relevant param-pvar
		    (member (PVAR-TO-TVAR pvar) mr-et-tvars)
		    (if ;n.c. cterm
		     (formula-of-nulltype? formula)
		     (myerror
		      "idpredconst-to-mr-idpredconst" "c.r. formula expected"
		      formula "for relevant param-pvar" pvar)
					;else c.r. cterm
		     (let* ((et-type (formula-to-et-type formula))
			    (mr-var (type-to-new-partial-var et-type))
			    (mr-vars (cons mr-var vars))
			    (mr-formula (real-and-formula-to-mr-formula-aux
					 (make-term-in-var-form mr-var)
					 formula)))
		       (list
			(PVAR-TO-MR-PVAR pvar)
			(apply make-cterm (append mr-vars (list mr-formula))))))
					;else irrelevant param-pvar.  Not used
		    (list pvar cterm))))
	       param-pvars cterms))
	 (orig-and-mr-cterms
	  (map (lambda (pvar)
		 (let ((info1 (assoc pvar pvar-cterm-alist))
		       (info2 (assoc pvar mr-pvar-cterm-alist)))
		   (cond (info1 (cadr info1))
			 (info2 (cadr info2))
			 (else (myerror "idpredconst-to-mr-idpredconst"
					"unexpected orig-and-mr-pvars"
					orig-and-mr-pvars)))))
	       orig-and-mr-pvars)))
    (make-idpredconst mr-idpc-name orig-and-mr-types orig-and-mr-cterms)))

(define (all-formulas-to-mr-ind-proof . all-formulas)
  (if (nested-alg-name?
       (alg-form-to-name (var-to-type (all-form-to-var (car all-formulas)))))
      (myerror "all-formulas-to-mr-ind-proof"
	       "all-formula for an unnested algebra expected"
	       (car all-formulas)
	       "unfold all-formula"))
  (let* ((free (apply union (map formula-to-free all-formulas)))
	 (vars (map all-form-to-var all-formulas))
	 (kernels (map all-form-to-kernel all-formulas))
	 (orig-ind-aconst (apply all-formulas-to-ind-aconst all-formulas))
	 (orig-inst-formula (aconst-to-inst-formula orig-ind-aconst))
	 (step-formulas ;D1 ... Dk
	  (imp-form-to-premises
	   (all-form-to-kernel orig-inst-formula)
	   (length (imp-form-to-premises
		    (all-form-to-kernel
		     (aconst-to-uninst-formula orig-ind-aconst))))))
	 (real-vars-with-eps ;f1 ... eps ... fk
	  (map (lambda (fla)
		 (let ((et-type (formula-to-et-type fla)))
		   (if (nulltype? et-type)
		       'eps
		       (type-to-new-partial-var et-type))))
	       step-formulas))
	 (real-terms-with-eps
	  (map (lambda (x)
		 (if (var-form? x)
		     (make-term-in-var-form x)
		     x))
	       real-vars-with-eps))
	 (avars ;u1: f1 mr D1 ... ui: eps mr Di ... uk: fk mr Dk
	  (map (lambda (r fla)
		 (formula-to-new-avar
		  (real-and-formula-to-mr-formula-aux r fla)
		  "u"))
	       real-terms-with-eps step-formulas))
	 (real-vars-with-eps-and-avars ;f1 u1 ... eps ui ... fk uk
	  (zip real-vars-with-eps avars))
	 (real-vars-and-avars ;f1 u1 ... ui ... fk uk
	  (list-transform-positive real-vars-with-eps-and-avars
	    (lambda (x) (not (equal? 'eps x)))))
	 (real-vars ;f1 ... fk
	  (list-transform-positive real-vars-and-avars var-form?))
         (real-terms
          (list-transform-positive real-terms-with-eps
	    (lambda (x) (not (equal? 'eps x)))))
	 (arrow-types (map formula-to-et-type all-formulas))
	 (proper-arrow-types
	  (list-transform-positive arrow-types
	    (lambda (x) (not (nulltype? x)))))
	 (rec-consts ;adapted to allnc free
	  (apply arrow-types-to-rec-consts proper-arrow-types))
         (rec-terms (map make-term-in-const-form rec-consts))
	 (alg-names-for-rec
	  (map (lambda (type)
		 (alg-form-to-name (arrow-form-to-arg-type type)))
	       proper-arrow-types))
	 (alg-names-with-rec-terms
	  (map list alg-names-for-rec rec-terms))
	 (fully-applied-rec-consts-or-eps
	  (do ((l1 arrow-types (cdr l1))
	       (l2 vars (cdr l2))
	       (l3 rec-terms
		   (if (nulltype? (car l1))
		       l3
		       (cdr l3)))
	       (res '() (cons (if (nulltype? (car l1))
				  'eps
				  (apply mk-term-in-app-form
					 (car l3)
					 (make-term-in-var-form (car l2))
					 real-terms))
			      res)))
	      ((null? l1) (reverse res))))
	 (mr-all-formulas
	  (map (lambda (var x kernel)
		 (make-all var (real-and-formula-to-mr-formula-aux x kernel)))
	       vars fully-applied-rec-consts-or-eps kernels))
	 (orig-uninst-step-formulas
	  (imp-form-to-premises
           (all-form-to-kernel (aconst-to-uninst-formula orig-ind-aconst))))
	 (component-lengths ;(s1 ... sk) with si=mi+ni
	  (map (lambda (x)
		 (length (car (all-form-to-vars-and-final-kernel x))))
	       orig-uninst-step-formulas))
	 (hyp-lengths ;(n1 ... nk)
	  (map (lambda (x)
		 (length (imp-form-to-premises
			  (cadr (all-form-to-vars-and-final-kernel x)))))
	       orig-uninst-step-formulas))
	 (param-lengths ;(m1 ... mk)
	  (map (lambda (s n) (- s n)) component-lengths hyp-lengths))
	 (mr-ind-aconst (apply all-formulas-to-ind-aconst mr-all-formulas))
	 (mr-inst-formula (aconst-to-inst-formula mr-ind-aconst))
	 (mr-step-formulas ;(D1^mr ... Dk^mr)
	  (imp-form-to-premises (all-form-to-kernel mr-inst-formula)
				(length orig-uninst-step-formulas)))
	 (var (all-form-to-var mr-inst-formula)) ;x_j
	 (var-lists ;((y1 ... ym y_{m+1} ... y_{m+n}) ...)
	  (map (lambda (s x)
		 (if (zero? s) '()
		     (list-head (car (all-form-to-vars-and-final-kernel x))
				s)))
	       component-lengths mr-step-formulas))
	 (prem-lists
	  (map (lambda (s n x)
		 (if (zero? s) '()
		     (list-head (imp-form-to-premises
				 (cadr (all-form-to-vars-and-final-kernel x)))
				n)))
	       component-lengths hyp-lengths mr-step-formulas))
	 (prem-avar-lists ;((v1 ... vn) ...)
	  (map (lambda (prems)
		 (map (lambda (fla) (formula-to-new-avar fla "v")) prems))
	       prem-lists))
	 (y-lists ;((y_{m+1} ... y_{m+n}) ...)
	  (map (lambda (l m) (list-tail l m)) var-lists param-lengths))
	 (prem-vars-lists ;list of lists of vec{x}'s
	  (map (lambda (prems ys)
		 (map (lambda (fla y)
			(list-head
			 (car (all-form-to-vars-and-final-kernel fla))
			 (length (arrow-form-to-arg-types (var-to-type y)))))
		      prems ys))
	       prem-lists y-lists))
	 (applied-y-lists
	  (map (lambda (ys prem-vars-list)
		 (map (lambda (y prem-vars)
			(apply mk-term-in-app-form
			       (map make-term-in-var-form
				    (cons y prem-vars))))
		      ys prem-vars-list))
	       y-lists prem-vars-lists))
	 (mr-step-formula-realizer-lists
	  (map (lambda (applied-y-list)
		 (map (lambda (term)
			(let ((info
			       (assoc (alg-form-to-name (term-to-type term))
				      alg-names-with-rec-terms)))
			  (if info
			      (apply mk-term-in-app-form
				     (cadr info)
				     (cons term real-terms))
			      'eps)))
		      applied-y-list))
	       applied-y-lists))
	 (mr-step-formula-realizer-and-prem-avar-lists
	  (map (lambda (mr-step-formula-realizers prem-avars)
		 (zip mr-step-formula-realizers prem-avars))
	       mr-step-formula-realizer-lists prem-avar-lists))
	 (mr-step-formula-real-term-and-prem-avar-lists
	  (map (lambda (mr-step-formula-realizers-and-prem-avars)
		 (list-transform-positive
		     mr-step-formula-realizers-and-prem-avars
		   (lambda (x) (not (equal? 'eps x)))))
	       mr-step-formula-realizer-and-prem-avar-lists))
	 (mr-step-proofs
	  (map (lambda (u ys l)
		 (let ((vs (list-transform-positive l avar-form?))
		       (varterms-and-avarproofs
			(map (lambda (x)
			       (cond
				((term-form? x) x)
				((avar-form? x) (make-proof-in-avar-form x))
				(else (myerror "term or avar expected" x))))
			     l)))
		   (apply
		    mk-proof-in-intro-form
		    (append
		     ys vs (list (apply mk-proof-in-elim-form
					(make-proof-in-avar-form u)
					(append (map make-term-in-var-form ys)
						varterms-and-avarproofs)))))))
	       avars
	       var-lists
	       mr-step-formula-real-term-and-prem-avar-lists)))
    (apply
     mk-proof-in-intro-form
     (append
      free
      (list
       (apply
	mk-proof-in-intro-form
        var
	(append
	 real-vars-and-avars
	 (list
	  (apply
	   mk-proof-in-elim-form
	   (make-proof-in-aconst-form mr-ind-aconst)
	   (append
	    (map make-term-in-var-form (formula-to-free mr-inst-formula))
	    (cons
	     (make-term-in-var-form var)
	     mr-step-proofs)))))))))))

(define (all-formula-to-mr-cases-proof all-formula)
  (let* ((free (formula-to-free all-formula))
	 (var (all-form-to-var all-formula))
	 (kernel (all-form-to-kernel all-formula))
	 (orig-cases-aconst (all-formula-to-cases-aconst all-formula))
	 (orig-inst-formula (aconst-to-inst-formula orig-cases-aconst))
	 (cases-step-formulas ;Di1 ... Diq
	  (imp-form-to-premises
	   (all-form-to-kernel orig-inst-formula)
	   (length (imp-form-to-premises
		    (all-form-to-kernel
		     (aconst-to-uninst-formula orig-cases-aconst)))))))
    (if
     (formula-of-nulltype? kernel)
     (let* ((mr-all-formula
	     (real-and-formula-to-mr-formula-aux 'eps all-formula))
	    (cases-aconst (all-formula-to-cases-aconst mr-all-formula)))
       (make-proof-in-aconst-form cases-aconst))
     (let* ((real-vars ;f1 ... fq
	     (map (lambda (fla)
		    (type-to-new-partial-var (formula-to-et-type fla)))
		  cases-step-formulas))
	    (real-terms (map make-term-in-var-form real-vars))
	    (avars ;u1: f1 mr Di1 ... uq: fq mr Diq
	     (map (lambda (r fla)
		    (formula-to-new-avar
		     (real-and-formula-to-mr-formula-aux r fla)
		     "u"))
		  real-terms cases-step-formulas))
	    (real-vars-and-avars ;f1 u1 ... fq uq
	     (zip real-vars avars))
	    (if-term (make-term-in-if-form
		      (make-term-in-var-form var) real-terms))
	    (mr-all-formula
	     (make-all var (real-and-formula-to-mr-formula-aux
			    if-term kernel)))
	    (cases-aconst (all-formula-to-cases-aconst mr-all-formula)))
       (apply
	mk-proof-in-intro-form
	(append
	 free
	 (list
	  (apply
	   mk-proof-in-intro-form
           var
	   (append
	    real-vars-and-avars
	    (list
	     (apply
	      mk-proof-in-elim-form
	      (make-proof-in-aconst-form cases-aconst)
	      (append
	       (map make-term-in-var-form (formula-to-free mr-all-formula))
	       (cons (make-term-in-var-form var)
		     (map make-proof-in-avar-form avars))))))))))))))

(define (gind-aconst-to-mr-gind-proof aconst)
  (let* ((uninst-gind-formula (aconst-to-uninst-formula aconst))
         (all-formula (car (aconst-to-repro-data aconst)))
         (free (formula-to-free all-formula))
         (measure-var-and-vars (all-form-to-vars uninst-gind-formula))
         (measure-var (car measure-var-and-vars))
         (vars (cdr measure-var-and-vars))
         (m (length vars))
         (kernel-formula (all-form-to-final-kernel all-formula m)) ;A(xs)
         (kernel-formula-et-type (formula-to-et-type kernel-formula))
	 (inst-formula (aconst-to-inst-formula aconst))
	 (prog-formula ;Prog_mu{xs | A(xs)}
	  (imp-form-to-premise (all-form-to-final-kernel inst-formula)))
	 (prog-formula-et-type (formula-to-et-type prog-formula))
	 (real-var (type-to-new-var prog-formula-et-type)) ;G
	 (real-term (make-term-in-var-form real-var))
	 (prog-avar ;v: G mr Prog_mu{xs | A(xs)}
	  (formula-to-new-avar
	   (real-and-formula-to-mr-formula-aux real-term prog-formula)
	   "v"))
	 (types (map term-to-type vars))
	 (tpsubst (aconst-to-tpsubst aconst))
	 (tsubst (list-transform-positive tpsubst
		   (lambda (x) (tvar-form? (car x)))))
	 (type-info (append types (list kernel-formula-et-type)))
	 (grec-const (type-info-to-grec-const type-info))
	 (grec-term (make-term-in-const-form grec-const)) ;[[GInd]]
	 (grecguard-const (type-info-to-grecguard-const type-info))
	 (grecguard-term (make-term-in-const-form grecguard-const))
	 (applied-grec-term
	  (apply mk-term-in-app-form
		 grec-term
		 (append (map make-term-in-var-form
			      measure-var-and-vars)
			 (list real-term))))
	 (mr-kernel-formula ;GRec mu xs G mr A(xs)
	  (real-and-formula-to-mr-formula-aux
	   applied-grec-term kernel-formula))
	 (mr-all-formula ;all xs.GRec mu xs G mr A(xs)
	  (apply mk-all (append vars (list mr-kernel-formula))))
	 (mr-free (formula-to-free mr-all-formula))
	 (mr-gind-aconst
	  (all-formula-and-number-to-gind-aconst mr-all-formula m))
	 (mr-gind-inst-formula
	  (aconst-to-inst-formula mr-gind-aconst))
	 (mr-measure-var (all-form-to-var mr-gind-inst-formula))
	 (mr-prog-formula
	  (imp-form-to-premise
	   (all-form-to-final-kernel mr-gind-inst-formula)))
	 (subst-mr-prog-formula
	  (formula-subst mr-prog-formula mr-measure-var
			 (make-term-in-var-form measure-var)))
	 (mr-prog-prem-avar ;u:all ys(mu ys<mu xs -> GRec mu ys G mr A(ys))
	  (formula-to-new-avar
	   (imp-form-to-premise
	    (all-form-to-final-kernel subst-mr-prog-formula)) "u"))
	 (new-vars (map var-to-new-var vars)) ;ys
	 (test-term ;mu ys<mu xs
	  (mk-term-in-app-form
	   (if (not (assoc "nat" ALGEBRAS))
	       (myerror "First execute (libload \"nat.scm\")")
	       (pt "NatLt"))
	   (apply mk-term-in-app-form
		  (map make-term-in-var-form
		       (cons measure-var new-vars)))
	   (apply mk-term-in-app-form
		  (map make-term-in-var-form
		       measure-var-and-vars))))
	 (prev-applied-grecguard-term ;GRecGuard mu ys G (mu xs<mu ys)
	  (apply mk-term-in-app-form
		 grecguard-term
		 (make-term-in-var-form measure-var)
		 (append (map make-term-in-var-form new-vars)
			 (list real-term test-term))))
	 (test-var (type-to-new-partial-var (py "boole")))
	 (prev-applied-grecguard-var-term
	  (apply mk-term-in-app-form
		 grecguard-term
		 (make-term-in-var-form measure-var)
		 (append (map make-term-in-var-form new-vars)
			 (list real-term
			       (make-term-in-var-form test-var)))))
	 (vars-to-new-vars-subst
	  (make-substitution vars (map make-term-in-var-form new-vars)))
	 (subst-kernel-formula
	  (formula-substitute kernel-formula vars-to-new-vars-subst))
	 (cterm (make-cterm test-var
			    (real-and-formula-to-mr-formula-aux
			     prev-applied-grecguard-var-term
			     subst-kernel-formula)))
					;this is a hack ... is there no better
					;way to do this substitution?
	 (tsubst-eq-compat-rev-proof
	  (proof-subst (make-proof-in-aconst-form eq-compat-rev-aconst)
		       (car (formula-to-tvars
			     (aconst-to-formula eq-compat-rev-aconst)))
		       (py "boole")))
	 (tpsubst-eq-compat-rev-proof
	  (proof-subst tsubst-eq-compat-rev-proof
		       (car (formula-to-pvars
			     (proof-to-formula tsubst-eq-compat-rev-proof)))
		       cterm))
	 (aux-avar (formula-to-new-avar (make-atomic-formula test-term)))
	 (aux-proof ;M' : all ys(mu ys<mu xs -> GRecGuard
					;mu ys G (mu ys<mu xs) mr A(ys))
	  (apply
	   mk-proof-in-intro-form
	   (append
	    new-vars
	    (list
	     aux-avar
	     (mk-proof-in-elim-form
	      tpsubst-eq-compat-rev-proof test-term (pt "True")
	      (mk-proof-in-elim-form
	       (make-proof-in-aconst-form
		(finalg-to-=-to-eq-aconst (py "boole")))
	       test-term (pt "True")
	       (mk-proof-in-elim-form
		(make-proof-in-aconst-form atom-true-aconst)
		test-term
		(make-proof-in-avar-form aux-avar)))
	      (apply mk-proof-in-elim-form
		     (make-proof-in-avar-form mr-prog-prem-avar)
		     (append (map make-term-in-var-form new-vars)
			     (list (make-proof-in-avar-form
				    aux-avar)))))))))
	 (mr-prog-proof ;M : Prog_mu{xs | GRec mu xs G mr A(xs)}
	  (apply
	   mk-proof-in-intro-form
	   (append
	    vars
	    (list
	     mr-prog-prem-avar
	     (apply
	      mk-proof-in-elim-form
	      (make-proof-in-avar-form prog-avar)
	      (append
	       (map make-term-in-var-form vars)
	       (list
		(apply mk-term-in-abst-form
		       (append new-vars
			       (list prev-applied-grecguard-term)))
		aux-proof))))))))
    (apply
     mk-proof-in-intro-form
     (append
      free
      (list
       (apply
	mk-proof-in-intro-form
	measure-var
	(append
	 vars
	 (list
	  real-var
	  prog-avar
	  (apply
	   mk-proof-in-elim-form
	   (make-proof-in-aconst-form mr-gind-aconst)
	   (append
	    (map make-term-in-var-form mr-free)
	    (list (make-term-in-var-form measure-var))
	    (map make-term-in-var-form vars)
	    (list mr-prog-proof)))))))))))

(define (type-to-inhabtotal-mr-proof type)
  (let* ((uninst-formula (aconst-to-uninst-formula inhabtotalmr-aconst))
	 (arg (car (predicate-form-to-args uninst-formula)))
	 (mr-tvar (term-to-type arg)))
    (cond
     ((tvar-form? type)
      (make-proof-in-aconst-form
       (aconst-substitute inhabtotalmr-aconst (make-subst mr-tvar type))))
     ((alg-form? type)
      (let* ((inhab (type-to-canonical-inhabitant type))
	     (inhab-const (term-in-const-form-to-const inhab))
	     (constr-name (const-to-name inhab-const))
	     (alg-name (alg-form-to-name type))
	     (char-list (string->list alg-name))
	     (capitalized-alg-name
	      (list->string
	       (cons (char-upcase (car char-list)) (cdr char-list))))
	     (clause-name
	      (string-append "Total" capitalized-alg-name constr-name "MR"))
	     (info (assoc clause-name THEOREMS)))
	(if info
	    (let ((theorem (cadr info))
		  (tsubst (make-subst mr-tvar type)))
	      (make-proof-in-aconst-form (aconst-substitute theorem tsubst)))
	    (myerror "type-to-inhabtotal-mr-proof"
		     "theorem name expected" clause-name))))
     ((arrow-form? type)
      (let* ((arg-type (arrow-form-to-arg-type type))
	     (val-type (arrow-form-to-val-type type))
	     (var (type-to-new-partial-var arg-type))
	     (real-var (type-to-new-partial-var arg-type))
	     (var-term (make-term-in-var-form var))
	     (real-var-term (make-term-in-var-form real-var))
	     (total-formula (make-total var-term))
	     (mr-prem (real-and-formula-to-mr-formula-aux
		       real-var-term total-formula))
	     (u (formula-to-new-avar mr-prem))
	     (prev (type-to-inhabtotal-mr-proof val-type)))
	(mk-proof-in-nc-intro-form var real-var u prev)))
     ((star-form? type)
      (let* ((left (star-form-to-left-type type))
	     (right (star-form-to-right-type type))
	     (prev-left (type-to-inhabtotal-mr-proof left))
	     (prev-right (type-to-inhabtotal-mr-proof right)))
	(make-proof-in-and-intro-form prev-left prev-right)))
     (else "type-to-inhabtotal-mr-proof"
	   "type of tvar-, alg-, arrow- or star-form expected" type))))

(define (ex-formula-to-ex-intro-mr-proof ex-formula)
  (let* ((free (formula-to-free ex-formula))
	 (var (ex-form-to-var ex-formula))
	 (kernel (ex-form-to-kernel ex-formula))
	 (kernel-type (formula-to-et-type kernel)))
    (if
     (nulltype? kernel-type)
     (let ((avar (formula-to-new-avar kernel "u")))
       (apply
	mk-proof-in-intro-form
	(append free (list var avar (make-proof-in-avar-form avar)))))
     (let* ((real-var (type-to-new-partial-var kernel-type))
	    (real-term (make-term-in-var-form real-var))
	    (mr-formula (real-and-formula-to-mr-formula-aux
			 real-term kernel))
	    (avar (formula-to-new-avar mr-formula "u")))
       (apply
	mk-proof-in-intro-form
	(append free (list var real-var avar
			   (make-proof-in-avar-form avar))))))))

(define (ex-formula-and-concl-to-ex-elim-mr-proof ex-formula concl)
  (let* ((free (union (formula-to-free ex-formula) (formula-to-free concl)))
	 (var (ex-form-to-var ex-formula))
	 (type (var-to-type var))
	 (kernel (ex-form-to-kernel ex-formula))
	 (kernel-type (formula-to-et-type kernel))
	 (ex-type (formula-to-et-type ex-formula))
	 (concl-type (formula-to-et-type concl)))
    (if
     (nulltype? kernel-type)
     (let* ((u (formula-to-new-avar kernel "u"))
	    (z (type-to-new-partial-var
		(formula-to-et-type
		 (make-all var (make-imp kernel concl)))))
	    (zx (make-term-in-app-form (make-term-in-var-form z)
				       (make-term-in-var-form var)))
	    (mr-concl (real-and-formula-to-mr-formula-aux zx concl))
	    (v (formula-to-new-avar
		(make-all var (make-imp kernel mr-concl)) "v"))
	    (elim-proof (mk-proof-in-elim-form
			 (make-proof-in-avar-form v)
			 (make-term-in-var-form var)
			 (make-proof-in-avar-form u))))
       (apply mk-proof-in-intro-form
	      (append free (list var u z v elim-proof))))
     (let* ((pair-var (type-to-new-partial-var (make-star type kernel-type)))
	    (pair-var-term (make-term-in-var-form pair-var))
	    (left-term (make-term-in-lcomp-form pair-var-term))
	    (right-term (make-term-in-rcomp-form pair-var-term))
	    (mr-kernel (real-and-formula-to-mr-formula-aux
			(make-term-in-rcomp-form pair-var-term)
			(formula-subst
			 kernel var (make-term-in-lcomp-form pair-var-term))))
	    (u (formula-to-new-avar mr-kernel "u"))
	    (y (type-to-new-partial-var (formula-to-et-type kernel)))
	    (y-mr-kernel (real-and-formula-to-mr-formula-aux
			  (make-term-in-var-form y) kernel))
	    (z (type-to-new-partial-var
		(formula-to-et-type
		 (make-all var (make-imp kernel concl)))))
	    (zxy (mk-term-in-app-form (make-term-in-var-form z)
				      (make-term-in-var-form var)
				      (make-term-in-var-form y)))
	    (mr-concl (real-and-formula-to-mr-formula-aux zxy concl))
	    (mr-kernel-with-var-and-y
	     (real-and-formula-to-mr-formula-aux
	      (make-term-in-var-form y) kernel))
	    (v (formula-to-new-avar
		(mk-all var y (make-imp mr-kernel-with-var-and-y
					mr-concl)) "v"))
	    (elim-proof (mk-proof-in-elim-form
			 (make-proof-in-avar-form v)
			 left-term right-term
			 (make-proof-in-avar-form u))))
       (apply mk-proof-in-intro-form
	      (append free (list (mk-proof-in-intro-form
				  pair-var u z v
				  elim-proof))))))))

(define (efq-ga-to-mr-efq-ga-proof aconst)
  (let* ((name (aconst-to-name aconst)) ;EfqLog or Efq
	 (kind (aconst-to-kind aconst)) ;global-assumption
	 (tpsubst (aconst-to-tpsubst aconst))
	 (tsubst (list-transform-positive tpsubst
		  (lambda (x) (tvar-form? (car x))))) ;empty
	 (psubst (list-transform-positive tpsubst
		  (lambda (x) (pvar-form? (car x)))))
	 (uninst-formula (aconst-to-uninst-formula aconst))
	 (fla1 (imp-form-to-conclusion uninst-formula))
	 (pvar (predicate-form-to-predicate fla1))
	 (cterm (if (pair? psubst)
		    (cadr (car psubst))
		    (make-cterm fla1)))
	 (fla (cterm-to-formula cterm))
	 (et-type (formula-to-et-type fla))
	 (real (type-to-canonical-inhabitant et-type))
	 (mr-fla (real-and-formula-to-mr-formula-aux real fla))
	 (new-cterm (make-cterm mr-fla))
	 (new-tpsubst (append tsubst (list (list pvar new-cterm))))
	 (new-aconst (make-aconst name kind uninst-formula new-tpsubst)))
    (make-proof-in-aconst-form new-aconst)))

(define (number-and-idpredconst-to-intro-mr-proof i idpc)
  (let* ((mr-idpc (idpredconst-to-mr-idpredconst idpc))
	 (intro-mr-aconst (number-and-idpredconst-to-intro-aconst i mr-idpc)))
    (make-proof-in-aconst-form intro-mr-aconst)))

(define (imp-formulas-to-mr-elim-proof . imp-formulas)
  (let* ((prems (map imp-form-to-premise imp-formulas))
	 (concls (map imp-form-to-conclusion imp-formulas))
	 (prem (car prems))
	 (concl (car concls))
	 (idpc (predicate-form-to-predicate prem))
	 (idpc-param-vars
	  (apply union (map cterm-to-free (idpredconst-to-cterms idpc))))
	 (prem-vars  (formula-to-free prem))
	 (concl-vars (formula-to-free concl))
	 (idpc-arg-vars (set-minus prem-vars idpc-param-vars)) ;xs
	 (vars ;w ...
	  (map
	   (lambda (prem)
	     (type-to-new-partial-var
	      (idpredconst-to-et-type (predicate-form-to-predicate prem))))
	   prems))
	 (mr-prems ;w mr I rs
	  (map (lambda (var prem)
		 (let ((idpc (predicate-form-to-predicate prem))
		       (args (predicate-form-to-args prem)))
		   (apply make-predicate-formula
			  (idpredconst-to-mr-idpredconst idpc)
			  (make-term-in-var-form var) args)))
	       vars prems))
	 (orig-elim-aconst (apply imp-formulas-to-elim-aconst imp-formulas))
	 (orig-uninst-formula (aconst-to-uninst-formula orig-elim-aconst))
	 (orig-uninst-clauses ;(K0 ... K{k-1})
	  (imp-form-to-premises (imp-form-to-conclusion orig-uninst-formula)))
	 (k (length orig-uninst-clauses))
	 (orig-inst-formula (aconst-to-inst-formula orig-elim-aconst))
	 (orig-inst-clauses ;Ki for i<k
	  (imp-form-to-premises (imp-form-to-conclusion orig-inst-formula) k))
	 (real-vars-with-eps ;w0 ... eps ... w{k-1}
	  (map (lambda (fla)
		 (let ((et-type (formula-to-et-type fla)))
		   (if (nulltype? et-type)
		       'eps
		       (type-to-new-partial-var et-type))))
	       orig-inst-clauses))
	 (real-terms-with-eps
	  (map (lambda (x)
		 (if (var-form? x)
		     (make-term-in-var-form x)
		     x))
	       real-vars-with-eps))
	 (avars ;u0: w0 mr K0 ... ui: eps mr Ki ... u{k-1}: w{k-1} mr K{k-1}
	  (map (lambda (r fla)
		 (formula-to-new-avar
		  (real-and-formula-to-mr-formula-aux r fla)
		  "u"))
	       real-terms-with-eps orig-inst-clauses))
	 (real-vars-with-eps-and-avars ;w0 u0 ... eps ui ... w{k-1} u{k-1}
	  (zip real-vars-with-eps avars))
	 (real-vars-and-avars ;w0 u0 ... ui ... w{k-1} u{k-1}
	  (list-transform-positive real-vars-with-eps-and-avars
	    (lambda (x) (not (equal? 'eps x)))))
	 (real-terms
	  (list-transform-positive real-terms-with-eps
	    (lambda (x) (not (eq? 'eps x)))))
	 (arrow-type-or-nulltype-list (map formula-to-et-type imp-formulas))
	 (arrow-types
	  (list-transform-positive arrow-type-or-nulltype-list arrow-form?))
	 (idpc-names (map (lambda (prem)
			    (idpredconst-to-name
			     (predicate-form-to-predicate prem)))
			  prems))
	 (mr-idpc-names (map (lambda (idpc-name)
			       (string-append idpc-name "MR"))
			     idpc-names))
	 (idpc-alg-names (map idpredconst-name-to-alg-name idpc-names))
	 (rec-const-or-eps-alist
	  (map (lambda (name type idpc-alg-name)
		 (list
		  name
		  (cond ((string=? idpc-alg-name "identity") 'identity)
			((arrow-form? type)
			 (apply arrow-types-to-rec-const
				(cons type (remove type arrow-types))))
			(else 'eps))))
	       mr-idpc-names arrow-type-or-nulltype-list idpc-alg-names))
	 (fully-applied-rec-const-or-eps-alist
	  (map (lambda (alist-pair var)
		 (cond ((eq? 'eps (cadr alist-pair)) alist-pair)
		       ((eq? 'identity (cadr alist-pair))
			(list
			 (car alist-pair)
			 (apply mk-term-in-app-form
				(append real-terms
					(list (make-term-in-var-form var))))))
		       (else
			(list
			 (car alist-pair)
			 (apply mk-term-in-app-form
				(make-term-in-const-form (cadr alist-pair))
				(make-term-in-var-form var)
				real-terms)))))
	       rec-const-or-eps-alist vars))
	 (mr-imp-formulas
	  (map (lambda (mr-prem x concl)
		 (make-imp mr-prem (real-and-formula-to-mr-formula-aux
				    x concl)))
	       mr-prems (map cadr fully-applied-rec-const-or-eps-alist) concls))
	 (mr-elim-aconst (apply imp-formulas-to-elim-aconst mr-imp-formulas))
	 (mr-imp-formula (car mr-imp-formulas))
	 (mr-prem (imp-form-to-premise mr-imp-formula))
	 (mr-idpc (predicate-form-to-predicate mr-prem))
	 (mr-idpc-param-vars
	  (apply union (map cterm-to-free (idpredconst-to-cterms mr-idpc))))
	 (mr-concl (imp-form-to-conclusion mr-imp-formula))
	 (mr-prem-vars (formula-to-free mr-prem))
	 (mr-concl-vars (formula-to-free mr-concl))
	 (mr-concl-rest-vars (set-minus mr-concl-vars mr-prem-vars))
	 (mr-prem-avar (formula-to-new-avar mr-prem)) ;of w mr I xs
	 (mr-clauses
	  (cdr (imp-form-to-premises
		(all-form-to-kernel
		 (aconst-to-inst-formula mr-elim-aconst)))))
	 (uninst-mr-clauses
	  (cdr (imp-form-to-premises
		(all-form-to-kernel
		 (aconst-to-uninst-formula mr-elim-aconst)))))
	 (mr-clause-proofs
	  (map ;as many as we have avars u0: w0 mr K0 ... ui: eps mr Ki ... 
					;u{k-1}: w{k-1} mr K{k-1}
	   (lambda (mr-clause uninst-mr-clause avar-proof)
	     (let* ((uninst-vars-and-prems
		     (imp-impnc-all-allnc-form-to-vars-and-premises
		      uninst-mr-clause))
		    (l (length uninst-vars-and-prems))
		    (vars-and-prems
		     (imp-impnc-all-allnc-form-to-vars-and-premises
		      mr-clause l))
		    (uninst-vars-and-avars
		     (map (lambda (uninst-var-or-prem)
			    (if (var-form? uninst-var-or-prem)
				uninst-var-or-prem
				(formula-to-new-avar uninst-var-or-prem)))
			  uninst-vars-and-prems))
		    (vars-and-avars
		     (map (lambda (var-or-prem)
			    (if (var-form? var-or-prem)
				var-or-prem
				(formula-to-new-avar var-or-prem)))
			  vars-and-prems))
		    (one-or-two-element-lists
		     (map
		      (lambda (var-or-avar uninst-var-or-avar)
			(if
			 (var-form? var-or-avar)
			 (list (make-term-in-var-form var-or-avar))
			 (let* ((avar-formula (avar-to-formula var-or-avar))
				(uninst-avar-formula
				 (avar-to-formula uninst-var-or-avar))
				(final-concl
				 (imp-impnc-all-allnc-form-to-final-conclusion
				  avar-formula))
				(uninst-final-concl
				 (imp-impnc-all-allnc-form-to-final-conclusion
				  uninst-avar-formula)))
			   (if
			    (and
			     (predicate-form? uninst-final-concl)
			     (let ((pred (predicate-form-to-predicate
					  uninst-final-concl)))
			       (and (idpredconst-form? pred)
				    (member (idpredconst-to-name pred)
					    mr-idpc-names)
				    (not (eq? 'eps
					      (cadr
					       (assoc
						(idpredconst-to-name pred)
						rec-const-or-eps-alist)))))))
					;two-element-list
			    (let* ((pred (predicate-form-to-predicate
					  final-concl))
				   (mr-idpc-name (idpredconst-to-name pred))
				   (rec-const
				    (cadr (assoc mr-idpc-name
						 rec-const-or-eps-alist)))
				   (mr-idpc-args
				    (predicate-form-to-args final-concl))
				   (fully-applied-f-term (car mr-idpc-args))
				   (ys-and-vs
				    (map term-in-var-form-to-var
					 (term-in-app-form-to-args
					  fully-applied-f-term))))
			      (list (make-proof-in-avar-form var-or-avar)
				    (apply
				     mk-term-in-abst-form
				     (append
				      ys-and-vs
				      (list
				       (apply mk-term-in-app-form
					      (make-term-in-const-form
					       rec-const)
					      fully-applied-f-term
					      real-terms))))))
					;else one-element-list
			    (list (make-proof-in-avar-form var-or-avar))))))
		      vars-and-avars
		      uninst-vars-and-avars))
		    (extended-vars-and-avars
		     (apply append one-or-two-element-lists)))
	       (apply mk-proof-in-intro-form
		      (append
		       vars-and-avars
		       (list (apply mk-proof-in-elim-form
				    avar-proof
				    extended-vars-and-avars))))))
	   mr-clauses
	   uninst-mr-clauses
	   (map make-proof-in-avar-form avars))))
    (apply mk-proof-in-intro-form
	   (append
	    (union prem-vars concl-vars)
	    (list (car vars) mr-prem-avar) ;w avar:w mr I xs
	    real-vars-and-avars
	    (list (apply
		   mk-proof-in-elim-form
		   (make-proof-in-aconst-form mr-elim-aconst)
		   (append
		    (map make-term-in-var-form idpc-arg-vars) ;xs
		    (map make-term-in-var-form mr-idpc-param-vars)
		    (map make-term-in-var-form mr-concl-rest-vars)
		    (cons (make-term-in-var-form (car vars)) ;w
			  (cons (make-proof-in-avar-form mr-prem-avar)
				mr-clause-proofs)))))))))

;; For andr-formula-and-concl-to-andr-elim-mr-proof the definition is
;; the same as for andl-formula-and-concl-to-andl-elim-mr-proof .
;; Thus we use andlr-formula-and-concl-to-andlr-elim-mr-proof

(define (andlr-formula-and-concl-to-andlr-elim-mr-proof andlr-formula concl)
  (let* ((andlr-vars (formula-to-free andlr-formula))
	 (concl-vars (formula-to-free concl))
	 (andlr-type (formula-to-et-type andlr-formula))
	 (real-var (type-to-new-partial-var andlr-type)) ;a
	 (real-term (make-term-in-var-form real-var))
	 (mr-andlr-fla ;a mr X andl Y^ or a mr X^ andr Y
	  (real-and-formula-to-mr-formula-aux real-term andlr-formula))
	 (mr-andlr-fla-avar (formula-to-new-avar mr-andlr-fla)) ;w
	 (concl-type (formula-to-et-type concl))
	 (f (type-to-new-partial-var (make-arrow andlr-type concl-type)))
	 (f-term (make-term-in-var-form f)) ;f
	 (app-term (make-term-in-app-form f-term real-term)) ;fa
	 (mr-concl ;fa mr concl
	  (real-and-formula-to-mr-formula-aux app-term concl))
	 (imp-fla (make-imp mr-andlr-fla mr-concl))
	 (elim-aconst (imp-formulas-to-elim-aconst imp-fla))
	 (free (append andlr-vars concl-vars))
	 (intro-proof
	  (apply mk-proof-in-intro-form
		 (append free (list (make-proof-in-aconst-form elim-aconst)))))
	 (elim-proof
	  (apply mk-proof-in-elim-form
		 intro-proof
		 (append (map make-term-in-var-form
			      (append andlr-vars (cons f concl-vars)))
			 (list real-term
			       (make-proof-in-avar-form mr-andlr-fla-avar))))))
    (apply mk-proof-in-intro-form
	   (append andlr-vars concl-vars
		   (list real-var mr-andlr-fla-avar f elim-proof)))))

(define (one-clause-nc-idpc-formula-and-concl-to-elim-mr-proof
	 one-clause-nc-idpc-formula concl)
  (let* ((concl-type (formula-to-et-type concl))
	 (real-var (type-to-new-partial-var concl-type))
	 (real (make-term-in-var-form real-var))
	 (mr-concl (real-and-formula-to-mr-formula-aux real concl))
	 (imp-mr-formula (make-imp one-clause-nc-idpc-formula mr-concl))
	 (mr-aconst (imp-formulas-to-elim-aconst imp-mr-formula)))
    (make-proof-in-aconst-form mr-aconst)))

(define (coidpredconst-to-closure-mr-proof coidpc)
  (let* ((closure-aconst (coidpredconst-to-closure-aconst coidpc))
	 (tpsubst (idpredconst-to-tpsubst coidpc))
	 (goal-formula (proof-to-soundness-formula
			(make-proof-in-aconst-form
			 (aconst-substitute closure-aconst tpsubst))))
	 (goal-vars (all-form-to-vars goal-formula))
	 (goal-kernel (all-form-to-final-kernel goal-formula))
	 (goal-prem (imp-form-to-premise goal-kernel))
	 (goal-prem-avar (formula-to-new-avar goal-prem))
	 (goal-concl (imp-form-to-conclusion goal-kernel))
	 (coidpc-avar (formula-to-new-avar goal-prem))
	 (mr-coidpc (idpredconst-to-mr-idpredconst coidpc))
	 (mr-closure-aconst (coidpredconst-to-closure-aconst mr-coidpc))
	 (mr-closure-concl-proof
	  (apply mk-proof-in-elim-form
		 (make-proof-in-aconst-form mr-closure-aconst)
		 (append (map make-term-in-var-form goal-vars)
			 (list
			  (make-proof-in-avar-form goal-prem-avar))))))
    (apply
     mk-proof-in-intro-form
     (append
      goal-vars
      (list
       (make-proof-in-imp-intro-form
	goal-prem-avar
	(make-proof-in-imp-elim-form
	 (coidpredconst-to-closure-mr-proof-or-elim
	  (rename-variables
	   (make-imp (proof-to-formula mr-closure-concl-proof) goal-concl))
	  #f)
	 mr-closure-concl-proof)))))))

(define (imp-formulas-to-mr-gfp-proof . imp-formulas)
  (let* ((gfp-aconst (apply imp-formulas-to-gfp-aconst imp-formulas))
	 (arrow-types (map formula-to-et-type imp-formulas))
	 (et-type (arrow-form-to-val-type (car arrow-types)))
	 (prem-type (arrow-form-to-arg-type (car arrow-types)))
	 (corec-consts
	   (apply alg-or-arrow-types-to-corec-consts arrow-types))
	 (corec-term (make-term-in-const-form (car corec-consts)))
	 (mr-formula ;; this is the goal formula to prove
	  (real-and-formula-to-mr-formula-aux
	   corec-term (aconst-to-formula gfp-aconst)))
	 (mr-vars (allnc-form-to-vars mr-formula))
	 (mr-kernel (allnc-form-to-final-kernel mr-formula))
	 (mr-competitor (imp-impnc-form-to-premise mr-kernel))
	 (mr-costeps-and-final-concl
	  ;; list of a var (realizer) and a formula for each costeps and
	  ;; a formula for the final concl of the form CoI u \vec{x}
	  ;; Eg. ((var_1 costep-fla_1) ... (var_k costep-fla_k) concl-fla)
	  (letrec
	      ((fla-to-costeps-and-concl
		(lambda (fla)
		  (if (predicate-form? fla)
		      (list fla)
		      (let*
			  ((var (all-allnc-form-to-var fla)) ;realizer
			   (kernel (all-allnc-form-to-final-kernel fla))
			   (prem (imp-impnc-form-to-premise kernel))
			   (concl (imp-impnc-form-to-conclusion kernel)))
			(cons (list var prem)
			      (fla-to-costeps-and-concl concl)))))))
	    (fla-to-costeps-and-concl
	     (imp-impnc-form-to-conclusion mr-kernel))))
	 (simul-num (- (length mr-costeps-and-final-concl) 1))
	 (mr-concl (list-ref mr-costeps-and-final-concl simul-num)) ;last elem
	 (mr-costeps (list-head mr-costeps-and-final-concl simul-num))
	 (mr-costep-realizer-vars (map car mr-costeps))
	 (mr-costep-flas (map cadr mr-costeps))
	 (mr-coidpredconst (predicate-form-to-predicate mr-concl))
	 (mr-coidpredconst-args (predicate-form-to-args mr-concl))
	 (mr-competitor-avar (formula-to-new-avar mr-competitor))
	 (mr-costep-avars (map formula-to-new-avar mr-costep-flas))
	 (mr-imp-formulas
	   (letrec
	       ((imp-fla-to-mr-imp-fla
		 (lambda (fla)
		   (let*
		       ((coidpc-fla (imp-impnc-form-to-conclusion fla))
			(prem-fla (imp-impnc-form-to-premise fla))
			(args (predicate-form-to-args coidpc-fla))
			(et-arrow-type (formula-to-et-type fla))
			(corec-arrow-types
			 (cons et-arrow-type
			       (remove et-arrow-type arrow-types)))
			(concl-et-type (arrow-form-to-val-type et-arrow-type))
			(prem-et-type (arrow-form-to-arg-type et-arrow-type))
			(ex-var (type-to-new-partial-var prem-et-type))
			(real-term (make-term-in-var-form
				    (type-to-new-partial-var concl-et-type)))
			(corec-term
			 (apply mk-term-in-app-form
				(make-term-in-const-form
				 (apply alg-or-arrow-types-to-corec-const
					corec-arrow-types))
				(map make-term-in-var-form
				     (cons ex-var mr-costep-realizer-vars))))
			(eqd-fla (make-eqd real-term corec-term))
			(prem-mr-fla
			 (real-and-formula-to-mr-formula
			  (make-term-in-var-form ex-var) prem-fla))
			(exu-fla
			 (make-exu ex-var (make-andu eqd-fla prem-mr-fla))))
		     (make-imp exu-fla (real-and-formula-to-mr-formula
					real-term coidpc-fla))))))
	     (map imp-fla-to-mr-imp-fla imp-formulas)))
	 (mr-gfp-aconst (apply imp-formulas-to-gfp-aconst mr-imp-formulas))
	 (mr-gfp-formula (aconst-to-formula mr-gfp-aconst))
	 (mr-gfp-inst-formula (aconst-to-inst-formula mr-gfp-aconst))
	 (mr-gfp-uninst-formula (aconst-to-uninst-formula mr-gfp-aconst))
	 (mr-gfp-prem (imp-impnc-form-to-premise
		       (allnc-form-to-final-kernel mr-gfp-formula)))
	 (mr-gfp-costep-formulas
	  (imp-impnc-form-to-premises (imp-impnc-form-to-conclusion
				       (allnc-form-to-final-kernel
					(aconst-to-formula mr-gfp-aconst)))))
	 (mr-gfp-arg-terms
	  (let* ((tsubst (make-substitution
			  (map term-in-var-form-to-var
			       (predicate-form-to-args
				(imp-impnc-all-allnc-form-to-final-conclusion
				 mr-gfp-formula)))
			  (predicate-form-to-args mr-concl)))
		 (arg-terms (map make-term-in-var-form
				 (all-allnc-form-to-vars mr-gfp-formula))))
	    (map (lambda (t) (term-substitute t tsubst)) arg-terms)))
	 (prem-and-costeps-imp-concl-proof
	  (apply mk-proof-in-elim-form
		 (make-proof-in-aconst-form mr-gfp-aconst) mr-gfp-arg-terms))
	 ;; we prepare a proof of the premise (competitor) of mr-gfp
	 (eqd-intro-proof
	  (make-proof-in-aconst-form
	    (number-and-idpredconst-to-intro-aconst
	     0 (idpredconst-name-and-types-and-cterms-to-idpredconst
		"EqD" (list et-type) '()))))
	 (mr-gfp-competitor-proof ; wrong! --> okay? (2014-05-26)
	   (let* ((exu-prem (imp-impnc-form-to-premise
			     (proof-to-formula
			      prem-and-costeps-imp-concl-proof)))
		  (exu-var (exu-form-to-var exu-prem))
		  (real-var (car (reverse mr-vars)))
		  (exu-kernel (exu-form-to-kernel exu-prem))
		  (cterm (make-cterm exu-var exu-kernel))
		  (exu-intro-proof
		   (make-proof-in-aconst-form
		    (number-and-idpredconst-to-intro-aconst
		     0 (idpredconst-name-and-types-and-cterms-to-idpredconst
			"ExU" (list prem-type) (list cterm)))))
		  (exu-intro-fla (proof-to-formula exu-intro-proof))
		  (exu-proof-vars (all-allnc-form-to-vars exu-intro-fla))
		  (eqd-imp-mr-gfp-prem-proof
		   (apply mk-proof-in-elim-form
			  exu-intro-proof
			  (map
			   make-term-in-var-form
			   (reverse
			    (cons real-var (cdr (reverse exu-proof-vars)))))))
		  (andu-proof
		   (let* ((andu-fla
			   (imp-impnc-form-to-premise
			    (proof-to-formula
			     eqd-imp-mr-gfp-prem-proof)))
			  (lft-fla (andu-form-to-left andu-fla))
			  (rgt-fla (andu-form-to-right andu-fla))
			  (eqd-arg
			   (car (predicate-form-to-args lft-fla)))
			  (andu-intro-proof
			   (make-proof-in-aconst-form
			    (number-and-idpredconst-to-intro-aconst
			     0
			     (idpredconst-name-and-types-and-cterms-to-idpredconst
			      "AndU" '()
			      (map make-cterm
				   (list lft-fla rgt-fla))))))
			  (andu-intro-fla (proof-to-formula andu-intro-proof))
			  (andu-vars (allnc-form-to-vars andu-intro-fla))
			  (eqd-inst-proof
			   (make-proof-in-allnc-elim-form eqd-intro-proof eqd-arg))
			  (subst
			   (caar
			    (apply
			     huet-unifiers
			     '() andu-vars '()
			     (map
			      list
			      (imp-impnc-all-allnc-form-to-premises andu-intro-fla)
			      (list (proof-to-formula eqd-inst-proof)
				    (avar-to-formula mr-competitor-avar))))))
			  (terms
			   (map (lambda (v) (term-substitute
					     (make-term-in-var-form v)
					     subst))
				andu-vars)))
		     (apply
		      mk-proof-in-elim-form
		      andu-intro-proof
		      (append terms
			      (list eqd-inst-proof
				    (make-proof-in-avar-form mr-competitor-avar))))))
		  (andu-fla (proof-to-formula andu-proof))
		  (subst
		   (caar (apply
			  huet-unifiers
			  (formula-to-free andu-fla)
			  (set-minus (all-allnc-form-to-vars exu-intro-fla)
				     (formula-to-free andu-fla))
			  '()
			  (map list
			       (imp-impnc-all-allnc-form-to-premises
				exu-intro-fla)
			       (list andu-fla)))))
		  (terms
		   (map (lambda (v) (term-substitute (make-term-in-var-form v)
						     subst))
			(all-allnc-form-to-vars exu-intro-fla)
			))
		  )
	     (apply
	      mk-proof-in-elim-form
	      exu-intro-proof (append terms (list andu-proof)))))
	 (costeps-imp-concl-proof
	  (mk-proof-in-elim-form
	   prem-and-costeps-imp-concl-proof mr-gfp-competitor-proof))
	 (costep-proofs
	  ;; from mr costeps, we are going to prove mr-gfp-costeps.
	  ;; It is important to know the corresponding assumption
	  ;; in the mr costep avars.
	  (imp-formulas-to-mr-gfp-proof-aux
	   mr-costep-avars
	   (imp-impnc-form-to-premises
	    (proof-to-formula costeps-imp-concl-proof))))
	 (concl-proof
	  (apply mk-proof-in-elim-form
		 costeps-imp-concl-proof costep-proofs)))
    (apply mk-proof-in-nc-intro-form
	   (append mr-vars (list mr-competitor-avar)
		   (zip mr-costep-realizer-vars mr-costep-avars)
		   (list concl-proof)))))

(define (term-to-eqd-proof term)
  (let* ((type (term-to-type term))
	 (idpc (make-idpredconst "EqD" (list type) '()))
	 (aconst (number-and-idpredconst-to-intro-aconst 0 idpc)))
    (mk-proof-in-elim-form (make-proof-in-aconst-form aconst) term)))

(define (imp-formulas-to-mr-gfp-proof-aux mr-costep-avars goals)
  (map
   (lambda (mr-costep-avar goal)
     (let* ((goal-vars (all-allnc-form-to-vars goal))
	    (goal-kernel (all-allnc-form-to-final-kernel goal))
	    (goal-prem (imp-impnc-form-to-premise goal-kernel))
	    (goal-prem-avar (formula-to-new-avar goal-prem))
	    (goal-prem-predicate (predicate-form-to-predicate goal-prem))
	    (goal-concl (imp-impnc-form-to-conclusion goal-kernel))
	    (exu-elim-aconst
	     (imp-formulas-to-elim-aconst (make-imp goal-prem goal-concl)))
	    (exu-elim-proof (make-proof-in-aconst-form exu-elim-aconst))
	    (exu-elim-fla (aconst-to-formula exu-elim-aconst))
	    (exu-elim-subst (all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
			exu-elim-fla (list goal-prem) goal-concl))
	    (exu-elim-vars (all-allnc-form-to-vars exu-elim-fla))
	    (exu-elim-inst-terms
	     (map (lambda (v) (term-substitute (make-term-in-var-form v)
					       exu-elim-subst))
		  exu-elim-vars))
	    (exu-elim-inst-kernel
	     (formula-substitute (all-allnc-form-to-final-kernel exu-elim-fla)
				 exu-elim-subst))
	    (exu-elim-inst-step
	     (cadr (imp-impnc-form-to-premises exu-elim-inst-kernel)))
	    (exu-elim-inst-step-vars (all-allnc-form-to-vars exu-elim-inst-step))
	    (exu-elim-inst-step-kernel
	     (all-allnc-form-to-final-kernel exu-elim-inst-step))
	    (exu-elim-inst-step-prem
	     (imp-impnc-form-to-premise exu-elim-inst-step-kernel))
	    (exu-elim-inst-step-prem-avar
	     (formula-to-new-avar exu-elim-inst-step-prem))
	    (exu-elim-inst-step-concl
	     (imp-impnc-form-to-conclusion exu-elim-inst-step-kernel))
	    (andu-elim-aconst
	     (imp-formulas-to-elim-aconst
	      (make-imp exu-elim-inst-step-prem exu-elim-inst-step-concl)))
	    (andu-elim-fla (aconst-to-formula andu-elim-aconst))
	    (andu-elim-vars (all-allnc-form-to-vars andu-elim-fla))
	    (andu-elim-subst
	     (all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
	      andu-elim-fla (list exu-elim-inst-step-prem) exu-elim-inst-step-concl))
	    (andu-elim-inst-terms
	     (map (lambda (v) (term-substitute (make-term-in-var-form v)
					       andu-elim-subst))
		  andu-elim-vars))
	    (andu-eilm-inst-kernel
	     (formula-substitute (all-allnc-form-to-final-kernel andu-elim-fla)
				 andu-elim-subst))
	    (andu-elim-inst-kernel-step
	     (cadr (imp-impnc-form-to-premises andu-eilm-inst-kernel)))
	    (andu-elim-inst-kernel-step-prems
	     (imp-impnc-form-to-premises andu-elim-inst-kernel-step))
	    (andu-elim-inst-kernel-step-prem-avars
	     (map formula-to-new-avar andu-elim-inst-kernel-step-prems))
	    (andu-elim-inst-kernel-step-concl
	     (imp-impnc-form-to-final-conclusion andu-elim-inst-kernel-step))
	    (mr-costep (avar-to-formula mr-costep-avar))
	    (mr-costep-vars (all-allnc-form-to-vars mr-costep))
	    (mr-costep-subst
	     (all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
	      mr-costep (list (cadr andu-elim-inst-kernel-step-prems))))
	    (mr-costep-inst-terms
	     (map (lambda (v) (term-substitute (make-term-in-var-form v)
					       mr-costep-subst))
		  mr-costep-vars))
	    (mr-costep-inst-kernel
	     (formula-substitute (all-allnc-form-to-final-kernel mr-costep)
				 mr-costep-subst))
	    (mr-costep-inst-kernel-concl
	     (imp-impnc-form-to-conclusion mr-costep-inst-kernel))
	    (mr-costep-concl-proof
	     (apply mk-proof-in-elim-form
		    (make-proof-in-avar-form mr-costep-avar)
		    (append mr-costep-inst-terms
			    (list (make-proof-in-avar-form
				   (cadr andu-elim-inst-kernel-step-prem-avars))))))
	    (disj-imp-disj-fla (make-impnc mr-costep-inst-kernel-concl
					   andu-elim-inst-kernel-step-concl))
	    (andu-elim-inst-kernel-step-eqd-prem-args
	     (predicate-form-to-args (car andu-elim-inst-kernel-step-prems)))
	    (eqd-compat-repl-var (term-in-var-form-to-var
				  (car andu-elim-inst-kernel-step-eqd-prem-args)))
	    (corec-eqd-compat-rev-at-allnc-fla
	     (make-allnc eqd-compat-repl-var
			 (make-eqd
			  (car andu-elim-inst-kernel-step-eqd-prem-args)
			  (nt
			   (undelay-delayed-corec
			    (cadr andu-elim-inst-kernel-step-eqd-prem-args) 1)))))
	    (corec-unfold-eqd-proof
	     (make-proof-in-aconst-form
	      (global-assumption-name-to-aconst
	       (alg-or-arrow-types-to-unfolded-corec-eqd-global-assumption-name
		(apply make-arrow (map var-to-type
				       (list (car exu-elim-inst-step-vars)
					     eqd-compat-repl-var)))))))
	    (corec-eqd-proof
	     (let* ((corec-args
		     (term-in-app-form-to-args
		      (cadr andu-elim-inst-kernel-step-eqd-prem-args)))
		    (corec-and-unfolded
		     (predicate-form-to-args (proof-to-formula ;;corec-eqd-proof-3)))
					      corec-unfold-eqd-proof)))
		    (corec-var1 (type-to-new-partial-var
				 (term-to-type (car corec-and-unfolded))))
		    (corec-var2 (type-to-new-partial-var
				 (term-to-type (car corec-and-unfolded))))
		    (corec-term1 (make-term-in-var-form corec-var1))
		    (corec-term2 (make-term-in-var-form corec-var2))
		    (arg-terms
		     (map (lambda (t) (nt (apply mk-term-in-app-form (cons t corec-args))))
			  (cons (make-term-in-var-form corec-var1)
				(cdr corec-and-unfolded))))
		    (unfolded-term (cadr corec-and-unfolded))
		    (unfolded-term-vars (term-in-abst-form-to-vars unfolded-term))
		    (unfolded-term-body (term-in-abst-form-to-final-kernel unfolded-term))
		    (eqd-concl-term
		     (let* ((tsubst (make-substitution unfolded-term-vars corec-args))
			    )
		       (term-substitute unfolded-term-body tsubst)))
		    (eqd-elim-aconst
		     (imp-formulas-to-elim-aconst
		      (make-imp
		       (make-eqd corec-term1 corec-term2)
		       (apply
			make-eqd
			(map
			 (lambda (t)
			   (apply mk-term-in-app-form t corec-args))
			 (list corec-term1 corec-term2))))))
		    (last-imp-proof
		     (apply mk-proof-in-elim-form
			    (make-proof-in-aconst-form eqd-elim-aconst)
			    (append
			     corec-and-unfolded
			     corec-args
			     (list corec-unfold-eqd-proof))))
		    (last-prem
		     (imp-impnc-form-to-premise
		      (proof-to-formula last-imp-proof)))
		    (last-vars (all-allnc-form-to-vars last-prem))
		    (last-kernel-eqd-term
		     (car (predicate-form-to-args
			   (all-allnc-form-to-final-kernel last-prem))))
		    )
	       (mk-proof-in-elim-form
		last-imp-proof
		(apply mk-proof-in-nc-intro-form
		       (snoc last-vars (term-to-eqd-proof last-kernel-eqd-term))))))
	    (andu-elim-inst-kernel-step-concl-inst
	     (formula-substitute
	      andu-elim-inst-kernel-step-concl
	      (make-subst (term-in-var-form-to-var
			   (car andu-elim-inst-kernel-step-eqd-prem-args))
			  (nt
			   (undelay-delayed-corec
			    (cadr andu-elim-inst-kernel-step-eqd-prem-args) 1)))))
	    (eqd-compat-proof
	     (eqd-compat-rev-at
	      (make-allnc (term-in-var-form-to-var
			   (car andu-elim-inst-kernel-step-eqd-prem-args))
			  andu-elim-inst-kernel-step-concl-inst)))
	    (eqd-compat-fla (proof-to-formula eqd-compat-proof))
	    (eqd-compat-vars (all-allnc-form-to-vars eqd-compat-fla))
	    (eqd-compat-subst
	     (all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
	      eqd-compat-fla (list (car andu-elim-inst-kernel-step-prems))))
	    (eqd-compat-terms
	     (map (lambda (v) (term-substitute (make-term-in-var-form v)
					       eqd-compat-subst))
		  eqd-compat-vars))
	    (disj-imp-disj-inst-fla
	     (make-imp
	      mr-costep-inst-kernel-concl
	      (formula-substitute (cadr (imp-impnc-form-to-premises
					 (all-allnc-form-to-final-kernel
					  eqd-compat-fla)))
				  eqd-compat-subst)))
	    (elim-term
	     (car (predicate-form-to-args mr-costep-inst-kernel-concl)))
	    (elim-term-type (term-to-type elim-term))
	    (elim-var (type-to-new-partial-var elim-term-type))
	    (gen-subst
	     (make-subst elim-term (make-term-in-var-form elim-var)))
	    (disj-imp-disj-inst-proof
	     (let* ((inst-goal
		     (make-allnc elim-var
				 (formula-gen-substitute disj-imp-disj-inst-fla
							 gen-subst))))
	       (mk-proof-in-elim-form
		(coidpredconst-to-closure-mr-proof-or-elim inst-goal #t)
		elim-term)))
	    (disj-inst-proof
	     (mk-proof-in-elim-form disj-imp-disj-inst-proof mr-costep-concl-proof))
	    (disj-inst-fla
	     (imp-impnc-form-to-conclusion disj-imp-disj-inst-fla))
	    (mr-costep-inst-kernel-concl-avar
	     (formula-to-new-avar mr-costep-inst-kernel-concl))
	    (andu-elim-concl-subst
	     (all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
	      andu-elim-fla (list exu-elim-inst-step-prem)))
	    (andu-elim-concl-terms2
	     (map (lambda (v) (term-substitute (make-term-in-var-form v)
					       andu-elim-concl-subst))
		  andu-elim-vars))
	    (term-eqd-unfolded-proof
	     (let* ((term1 (car (predicate-form-to-args (car andu-elim-inst-kernel-step-prems))))
		    (term2
		     (cadr
		      (predicate-form-to-args (proof-to-formula corec-eqd-proof))))
		    (goal-eqd-allnc-fla
		     (make-allnc (term-in-var-form-to-var term1)
				 (make-eqd term1 term2)))
		    )
	       (apply mk-proof-in-elim-form
		      (eqd-compat-rev-at goal-eqd-allnc-fla)
		      (list
		       term1
		       (cadr (predicate-form-to-args (car andu-elim-inst-kernel-step-prems)))
		       (make-proof-in-avar-form
			(car andu-elim-inst-kernel-step-prem-avars))
		       corec-eqd-proof))))
	    (term-eqd-unfolded-fla
	     (proof-to-formula term-eqd-unfolded-proof))
	    (disj-proof-4
	     (let*
		 ((args (map nt (predicate-form-to-args term-eqd-unfolded-fla)))
		  (gen-subst (make-subst (cadr args) (car args)))
		  (disj-fla-2
		   (formula-gen-substitute disj-inst-fla gen-subst))
		  (eqd-compat-allnc-fla
		   (make-allnc (term-in-var-form-to-var (car args))
			       disj-fla-2))
		  (compat-proof (eqd-compat-rev-at eqd-compat-allnc-fla)))
	       (apply mk-proof-in-elim-form
		      compat-proof
		      (append args
			      (list term-eqd-unfolded-proof
				    disj-inst-proof)))))
	    (andu-elim-concl-proof
	     (apply
	      mk-proof-in-elim-form
	      (make-proof-in-aconst-form andu-elim-aconst)
	      (append
	       andu-elim-concl-terms2
	       (list
		(make-proof-in-avar-form exu-elim-inst-step-prem-avar)
		(apply
		 mk-proof-in-nc-intro-form
		 (append
		  andu-elim-inst-kernel-step-prem-avars
		  (list disj-proof-4)))))))
	    (exu-elim-concl-proof
	     (apply
	      mk-proof-in-elim-form
	      (make-proof-in-aconst-form exu-elim-aconst)
	      (append
	       exu-elim-inst-terms
	       (list
		(make-proof-in-avar-form goal-prem-avar)
		(apply
		 mk-proof-in-nc-intro-form
		 (append
		  exu-elim-inst-step-vars
		  (list
		   exu-elim-inst-step-prem-avar
		   andu-elim-concl-proof))))))))
       (apply
	mk-proof-in-nc-intro-form
	(append goal-vars (list goal-prem-avar exu-elim-concl-proof)))))
   mr-costep-avars goals))

(define (alg-or-arrow-types-to-unfolded-corec-eqd-global-assumption-name
	 . alg-or-arrow-types)
  (let* ((name
	  (apply string-append
		 (cons "EQD-COREC-" (map type-to-string alg-or-arrow-types))))
	 (info (assoc name GLOBAL-ASSUMPTIONS)))
    (if (pair? info)
	name
	(let* ((consts
		(apply alg-or-arrow-types-to-corec-consts alg-or-arrow-types))
	       (corec-term (make-term-in-const-form (car consts)))
	       (unfolded-corec-term (nt (undelay-delayed-corec corec-term 1))))
	  (add-global-assumption name (make-eqd corec-term unfolded-corec-term))
	  name))))

;; It automates a unification problem frequently required in proof construction.
;; Assume formula is all/allnc_\vec{x}(A_0 ->/--> .. ->/--> A_k),
;; prem-flas is a list of B_0, ..., B_l where l < k, and
;; opt-goal-fla is optionally a formula.
;; This procedure finds a substitution from \vec{x} to terms \vec{t}
;; such that A_{l+1} ->/--> ... ->/--> A_k is derived from proofs
;; of formula and prem-flas by means of all/allnc elim and imp/impnc elim.
(define (all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
	 formula prem-flas . opt-goal-fla)
  (let* ((vars (all-allnc-form-to-vars formula))
	 (kernel (all-allnc-form-to-final-kernel formula))
	 (prems (imp-impnc-form-to-premises kernel))
	 (concl (imp-impnc-form-to-final-conclusion kernel))
	 (unif-pairs
	  (let* ((rel-prems (list-head prems (length prem-flas)))
		 (prem-pairs
		  (map (lambda (fla0 fla1) (list (nf fla0) (nf fla1)))
		       rel-prems prem-flas)))
	    (if (pair? opt-goal-fla)
		(cons (list concl (car opt-goal-fla)) prem-pairs)
		prem-pairs)))
	 (sig-vars
	  (set-minus (apply union (map formula-to-free (map cadr unif-pairs)))
		     vars))
	 (huet (apply huet-unifiers sig-vars vars '() (cons #t unif-pairs))))
    (if (pair? huet) (caar huet) #f)))

(define (str-gfp-proof-helper formula assumption)
  (let*
      ((mr-or-fla (avar-to-formula assumption))
       (mr-or-elim-term (car (predicate-form-to-args mr-or-fla)))
       (mr-or-elim-var (type-to-new-partial-var (term-to-type mr-or-elim-term)))
       (mr-or-imp-fla
	(formula-gen-substitute (make-imp mr-or-fla formula)
				(make-subst mr-or-elim-term
					    (make-term-in-var-form mr-or-elim-var))))
       (mr-or-elim-aconst (imp-formulas-to-elim-aconst mr-or-imp-fla))
       (mr-or-elim-fla (aconst-to-formula mr-or-elim-aconst))
       (mr-or-elim-vars (all-allnc-form-to-vars mr-or-elim-fla))
       (mr-or-elim-kernel (all-allnc-form-to-final-kernel mr-or-elim-fla))
       (mr-or-elim-prems (imp-impnc-form-to-premises mr-or-elim-kernel))
       (mr-or-elim-concl (imp-impnc-form-to-conclusion mr-or-elim-kernel))
       (mr-or-elim-subst
	(append (all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
		 mr-or-elim-fla (list mr-or-fla))
		(make-subst mr-or-elim-var mr-or-elim-term)))
       (mr-or-elim-terms
	(map
	 (lambda (v) (term-substitute (make-term-in-var-form v) mr-or-elim-subst))
	 mr-or-elim-vars))
       (mr-or-elim-step-flas
	(map (lambda (fla) (formula-substitute fla mr-or-elim-subst))
	     (cdr mr-or-elim-prems)))
       (mr-or-elim-first-step-proof
	(let* ((first-fla (car mr-or-elim-step-flas))
	       (first-vars (all-allnc-form-to-vars first-fla))
	       (first-kernel (all-allnc-form-to-final-kernel first-fla))
	       (first-prem (imp-impnc-form-to-premise first-kernel))
	       (first-prem-avar (formula-to-new-avar first-prem))
	       (first-concl (imp-impnc-form-to-conclusion first-kernel))
	       (first-ornc-intro-aconst
		(number-and-idpredconst-to-intro-aconst
		 0 (predicate-form-to-predicate first-concl)))
	       (first-ornc-intro-fla (aconst-to-formula first-ornc-intro-aconst))
	       (first-ornc-intro-vars (all-allnc-form-to-vars first-ornc-intro-fla))
	       (first-ornc-intro-kernel
		(all-allnc-form-to-final-kernel first-ornc-intro-fla))
	       (first-ornc-intro-prem
		(imp-impnc-form-to-premise first-ornc-intro-kernel))
	       (first-ornc-intro-concl
		(imp-impnc-form-to-conclusion first-ornc-intro-kernel))
	       (first-ornc-intro-subst
		(all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
		 first-ornc-intro-fla (list first-prem)))
	       (first-ornc-intro-terms
		(map
		 (lambda (v)
		   (term-substitute (make-term-in-var-form v)
				    first-ornc-intro-subst))
		 first-ornc-intro-vars)))
	  (apply
	   mk-proof-in-nc-intro-form
	   (append
	    first-vars
	    (list
	     first-prem-avar
	     (apply
	      mk-proof-in-elim-form
	      (make-proof-in-aconst-form first-ornc-intro-aconst)
	      (append first-ornc-intro-terms
		      (list (make-proof-in-avar-form first-prem-avar)))))))))
       (mr-or-elim-second-step-proof
	(let* ((second-fla (cadr mr-or-elim-step-flas))
	       (second-vars (all-allnc-form-to-vars second-fla))
	       (second-kernel (all-allnc-form-to-final-kernel second-fla))
	       (second-prem (imp-impnc-form-to-premise second-kernel))
	       (second-prem-avar (formula-to-new-avar second-prem))
	       (second-concl (imp-impnc-form-to-conclusion second-kernel))
	       (second-ornc-intro-aconst
		(number-and-idpredconst-to-intro-aconst
		 1 (predicate-form-to-predicate second-concl)))
	       (second-ornc-intro-fla
		(aconst-to-formula second-ornc-intro-aconst))
	       (second-ornc-intro-vars
		(all-allnc-form-to-vars second-ornc-intro-fla))
	       (second-ornc-intro-kernel
		(all-allnc-form-to-final-kernel second-ornc-intro-fla))
	       (second-ornc-intro-prem
		(imp-impnc-form-to-premise second-ornc-intro-kernel))
	       (second-ornc-intro-concl
		(imp-impnc-form-to-conclusion second-ornc-intro-kernel))
	       (second-ornc-intro-subst
		(all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
		 second-ornc-intro-fla '() second-concl))
	       (second-ornc-intro-terms
		(map (lambda (v) (term-substitute (make-term-in-var-form v)
		 				  second-ornc-intro-subst))
		     second-ornc-intro-vars))
	       (second-exu-goal
		(formula-substitute second-ornc-intro-prem second-ornc-intro-subst))
	       (second-exu-intro-aconst
		(number-and-idpredconst-to-intro-aconst
		 0 (predicate-form-to-predicate second-exu-goal)))
	       (second-exu-intro-fla (aconst-to-formula second-exu-intro-aconst))
	       (second-exu-intro-vars (all-allnc-form-to-vars second-exu-intro-fla))
	       (second-exu-intro-kernel
		(all-allnc-form-to-final-kernel second-exu-intro-fla))
	       (second-exu-intro-prem
		(imp-impnc-form-to-premise second-exu-intro-kernel))
	       (second-exu-intro-concl
		(imp-impnc-form-to-conclusion second-exu-intro-kernel))
	       (second-exu-vars-and-conjs
		(and-andi-ex-exi-formula-to-vars-and-conjuncts
		 second-exu-intro-concl))
	       (second-exu-vars (car second-exu-vars-and-conjs))
	       (second-exu-conjs (cadr second-exu-vars-and-conjs))
	       (second-exu-intro-concl-vars
		(exu-form-to-vars second-exu-intro-concl))
	       (second-exu-intro-concl-kernel
		(exu-form-to-final-kernel second-exu-intro-concl))
	       (second-exu-intro-subst
		(let* ((rconj (andu-form-to-right second-exu-intro-prem))
		       (unif-var (term-in-var-form-to-var
				  (car (predicate-form-to-args rconj)))))
		  (caar
		   (apply huet-unifiers
			  (remove unif-var (formula-to-free second-exu-intro-prem))
			  (list unif-var)
			  '()
			  (list #t (list second-prem rconj))))))
	       (second-andu-goal
		(formula-substitute second-exu-intro-prem second-exu-intro-subst))
	       (second-exu-intro-terms
		(map (lambda (v) (term-substitute (make-term-in-var-form v)
						  second-exu-intro-subst))
		     second-exu-intro-vars))
	       (second-andu-intro-aconst
		(number-and-idpredconst-to-intro-aconst
		 0 (predicate-form-to-predicate second-andu-goal)))
	       (second-andu-intro-fla (aconst-to-formula second-andu-intro-aconst))
	       (second-andu-intro-vars
		(all-allnc-form-to-vars second-andu-intro-fla))
	       (second-andu-intro-subst
		(all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
		 second-andu-intro-fla '() second-andu-goal))
	       (second-andu-intro-terms
		(map (lambda (v) (term-substitute (make-term-in-var-form v)
						  second-andu-intro-subst))
		     second-andu-intro-vars))
	       (second-andu-intro-kernel
		(all-allnc-form-to-final-kernel second-andu-intro-fla))
	       (second-andu-intro-prems
		(imp-impnc-form-to-premises second-andu-intro-kernel))
	       (second-eqd-goal (formula-substitute (car second-andu-intro-prems)
						    second-andu-intro-subst))
	       (second-eqd-proof
		(mk-proof-in-elim-form
		 (make-proof-in-aconst-form
		  (number-and-idpredconst-to-intro-aconst
		   0 (predicate-form-to-predicate second-eqd-goal)))
		 (term-substitute
		  (cadr (predicate-form-to-args second-eqd-goal))
		  second-exu-intro-subst)))
	       (second-mr-competitor-goal
		(formula-substitute (cadr second-andu-intro-prems)
				    second-andu-intro-subst))
	       (second-mr-competitor-proof
		(make-proof-in-avar-form second-prem-avar))
	       (second-andu-eqd-fla
		(formula-substitute (car second-exu-conjs) second-exu-intro-subst))
	       (second-andu-subst
		(all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
		 second-andu-intro-fla
		 (list second-eqd-goal second-prem)))
	       (second-andu-proof
		(apply mk-proof-in-elim-form
		       (make-proof-in-aconst-form second-andu-intro-aconst)
		       (append second-andu-intro-terms
			       (list second-eqd-proof second-mr-competitor-proof))))
	       (exu-proof-acasca
		(make-proof-in-avar-form
		 (formula-to-new-avar second-exu-goal)))
	       (second-exu-proof
		(apply mk-proof-in-elim-form
		       (make-proof-in-aconst-form second-exu-intro-aconst)
		       (append second-exu-intro-terms
			       (list second-andu-proof))))
	       (exu-subst2
		(all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
		 second-exu-intro-fla
		 (list
		  (formula-substitute
		   (make-andu second-andu-eqd-fla second-prem)
		   second-andu-subst))
		 second-exu-goal))
	       (exu-proof-terms2
		(map (lambda (v) (term-substitute (make-term-in-var-form v)
						  exu-subst2))
		     second-exu-intro-vars)))
	  (apply mk-proof-in-nc-intro-form
		 (append
		  second-vars
		  (list second-prem-avar
			(apply
			 mk-proof-in-elim-form
			 (make-proof-in-aconst-form second-ornc-intro-aconst)
			 (append
			  second-ornc-intro-terms
			  (list second-exu-proof)))))))))
    (apply mk-proof-in-elim-form
	   (make-proof-in-aconst-form mr-or-elim-aconst)
	   (append mr-or-elim-terms
		   (list (make-proof-in-avar-form assumption)
			 mr-or-elim-first-step-proof
			 mr-or-elim-second-step-proof)))))

(define (coidpredconst-to-closure-mr-proof-or-intro
	 formula gfp-info-or-f . assumptions)
  (let* ((vars-and-kernel ;; no check needed?
	  (all-allnc-form-to-vars-and-final-kernel formula))
	 (vars (car vars-and-kernel))
	 (kernel (cadr vars-and-kernel))
	 (prems (imp-impnc-form-to-premises kernel))
	 (prem-avars (map formula-to-new-avar prems))
	 (concl (imp-impnc-form-to-final-conclusion kernel))
	 (relevant-avars
	  (filter (lambda (a)
		    (classical-formula=? (avar-to-formula a) formula))
		  (filter avar-form? assumptions))))
    (cond
     ((pair? relevant-avars)
      (make-proof-in-avar-form (car relevant-avars)))
     ((all-allnc-form? formula)
      (apply mk-proof-in-nc-intro-form
	     (append (all-allnc-form-to-vars formula)
		     (list (apply coidpredconst-to-closure-mr-proof-or-intro
				  (all-allnc-form-to-final-kernel formula)
				  gfp-info-or-f assumptions)))))
     ((imp-impnc-form? formula)
      (let* ((prems (imp-impnc-form-to-premises formula))
	     (prem-avars (map formula-to-new-avar prems)))
	(apply mk-proof-in-nc-intro-form
	       (append prem-avars
		       (list (apply coidpredconst-to-closure-mr-proof-or-intro
				    (imp-impnc-form-to-conclusion formula)
				    gfp-info-or-f
				    (append assumptions prem-avars)))))))
     ((and (ori-mr-ori-form? concl)
	   (integer? (car assumptions)))
      (let* ((idpc (predicate-form-to-predicate concl))
	     (intro-aconst (number-and-idpredconst-to-intro-aconst
			    (car assumptions) idpc))
	     (intro-fla (aconst-to-formula intro-aconst))
	     (flex-vars (all-allnc-form-to-vars intro-fla))
	     (intro-kernel (all-allnc-form-to-final-kernel intro-fla))
	     (intro-prems (imp-impnc-form-to-premises intro-kernel))
	     (intro-final-concl
	       (imp-impnc-form-to-final-conclusion intro-kernel))
	     (subst
	       (caar (apply huet-unifiers
			    (formula-to-free formula) flex-vars '()
			    (list #t (list formula intro-final-concl)))))
	     (terms
	       (map
		(lambda (v) (term-substitute (make-term-in-var-form v) subst))
		flex-vars))
	     (subst-prems
	       (map (lambda (f) (formula-substitute f subst))
		    intro-prems))
	     (subst-prem-proofs
	       (map
		(lambda (f)
		  (apply
		   coidpredconst-to-closure-mr-proof-or-intro
		   f gfp-info-or-f (cdr assumptions)))
		subst-prems)))
	(apply mk-proof-in-nc-intro-form
	       (append vars prem-avars
		       (list (apply mk-proof-in-elim-form
				    (make-proof-in-aconst-form intro-aconst)
				    (append terms subst-prem-proofs)))))))
     ((and (ori-mr-ori-form? concl)
	   (not (integer? (car assumptions))))
      (str-gfp-proof-helper concl (car assumptions)))
     ((exi-mr-exi-form? concl)
      (let* ((idpc (predicate-form-to-predicate concl))
	     (intro-aconst
	      (number-and-idpredconst-to-intro-aconst 0 idpc))
	     (intro-fla (nf (aconst-to-formula intro-aconst)))
	     (flex-vars (all-allnc-form-to-vars intro-fla))
	     (intro-kernel (all-allnc-form-to-final-kernel intro-fla))
	     (intro-prems (imp-impnc-form-to-premises intro-kernel))
	     (intro-prem (car intro-prems))
	     (intro-final-concl
	       (imp-impnc-form-to-final-conclusion intro-kernel))
	     (intro-prem-exi-vars
	       (exi-mr-exi-form-to-vars intro-prem))
	     (intro-prem-exi-kernel
	       (exi-mr-exi-form-to-final-kernel intro-prem))
	     (vars-and-conjs
	       (and-andi-ex-exi-formula-to-vars-and-conjuncts
		intro-prem-exi-kernel))
	     (prem-vars (car vars-and-conjs))
	     (conjs (cadr vars-and-conjs))
	     (avar-flas (map nf (map avar-to-formula assumptions)))
	     (subst
	      (if (= (length conjs) (length assumptions))
		  (caar
		   (apply huet-unifiers
			  (apply union (map formula-to-free avar-flas))
			  (append flex-vars prem-vars intro-prem-exi-vars) '()
			  (cons
			   #t
			   (map list conjs avar-flas))))
		  (let* ((eqd-fla
			  (rac ((repeated rdc (length intro-prem-exi-vars))
				((repeated cdr (length assumptions)) conjs))))
			 (eqd-term-pair (predicate-form-to-args eqd-fla))
			 (sig-vars (term-to-free (car eqd-term-pair)))
			 (flex-vars (set-minus
				     (term-to-free (cadr eqd-term-pair))
				     sig-vars)))
		    (caar (apply huet-unifiers sig-vars flex-vars '()
				 (cons #t (cons eqd-term-pair '())))))))
	     (terms
	      (map
	       (lambda (v) (term-substitute (make-term-in-var-form v) subst))
	       flex-vars))
	     (subst-prems
	      (map (lambda (f) (formula-substitute f subst))
		   intro-prems))
	     (subst-prem-proofs
	      (map
	       (lambda (f)
		 (apply
		  coidpredconst-to-closure-mr-proof-or-intro
		  f gfp-info-or-f assumptions))
	       subst-prems)))
	(apply mk-proof-in-nc-intro-form
	       (append vars prem-avars
		       (list
			(apply mk-proof-in-elim-form
			       (make-proof-in-aconst-form intro-aconst)
			       (append terms subst-prem-proofs)))))))
     ((ex-form? concl)
      (let* ((intro-aconst (ex-formula-to-ex-intro-aconst concl))
	     (intro-fla (aconst-to-formula intro-aconst))
	     (intro-vars (all-allnc-form-to-vars intro-fla))
	     (intro-kernel (all-allnc-form-to-final-kernel intro-fla))
	     (intro-prems (imp-impnc-form-to-premises intro-kernel))
	     (subst
	      (all-allnc-form-and-prems-and-opt-goal-fla-to-unifier
	       intro-fla '() concl))
     	     (terms
     	      (map
     	       (lambda (v)
     		 (term-substitute (make-term-in-var-form v) subst))
	       intro-vars))
     	     (subst-prems
     	      (map (lambda (f) (formula-substitute f subst))
     		   intro-prems))
     	     (subst-prem-proofs
     	      (map
     	       (lambda (f)
     		 (apply
     		  coidpredconst-to-closure-mr-proof-or-intro
     		  f gfp-info-or-f assumptions))
     	       subst-prems)))
     	(apply mk-proof-in-nc-intro-form
     	       (append vars prem-avars
     		       (list
     			(apply mk-proof-in-elim-form
     			       (make-proof-in-aconst-form intro-aconst)
     			       (append terms subst-prem-proofs)))))))
     ((andi-mr-andi-form? concl)
      (let* ((idpc (predicate-form-to-predicate concl))
	     (intro-aconst (number-and-idpredconst-to-intro-aconst
			    0 idpc))
	     (intro-fla (aconst-to-formula intro-aconst))
	     (flex-vars (all-allnc-form-to-vars intro-fla))
	     (intro-kernel (all-allnc-form-to-final-kernel intro-fla))
	     (intro-prems (imp-impnc-form-to-premises intro-kernel))
	     (intro-final-concl
	      (imp-impnc-form-to-final-conclusion intro-kernel))
	     (subst
	      (caar (apply huet-unifiers
			   (formula-to-free formula)
			   flex-vars '()
			   (list #t (list formula intro-final-concl)))))
	     (terms
	      (map
	       (lambda (v)
		 (term-substitute (make-term-in-var-form v) subst))
	       flex-vars))
	     (subst-prems
	      (map (lambda (f) (formula-substitute f subst))
		   intro-prems))
	     (subst-prem-proof-1
	      (coidpredconst-to-closure-mr-proof-or-intro
	       (car subst-prems) gfp-info-or-f (car assumptions)))
	     (subst-prem-proof-2
	      (apply coidpredconst-to-closure-mr-proof-or-intro
		     (cadr subst-prems) gfp-info-or-f (cdr assumptions)))
	     (subst-prem-proofs
	      (list subst-prem-proof-1 subst-prem-proof-2)))
	(apply mk-proof-in-nc-intro-form
	       (append vars prem-avars
		       (list
			(apply mk-proof-in-elim-form
			       (make-proof-in-aconst-form intro-aconst)
			       (append terms subst-prem-proofs)))))))
     ((and-form? concl)
      ; make-proof-in-and-intro-form
      (let* ((lfla (and-form-to-left concl))
	     (rfla (and-form-to-right concl))
	     (lasm (if (pair? assumptions) (car assumptions) '()))
	     (rasms (if (pair? assumptions) (cdr assumptions) '()))
	     (lproof (coidpredconst-to-closure-mr-proof-or-intro
		      lfla gfp-info-or-f lasm))
	     (rproof (apply coidpredconst-to-closure-mr-proof-or-intro
			    rfla gfp-info-or-f rasms)))
	(apply mk-proof-in-nc-intro-form
	       (append vars prem-avars
		       (list
			(make-proof-in-and-intro-form lproof rproof))))))
     ((and (eqd-form? concl)
	   (apply term=? (map nt (predicate-form-to-args concl))))
      (let* ((idpc (predicate-form-to-predicate concl))
	     (intro-aconst (number-and-idpredconst-to-intro-aconst 0 idpc))
	     (term (car (predicate-form-to-args concl))))
	(apply mk-proof-in-nc-intro-form
	       (append vars prem-avars
		       (list
			(mk-proof-in-elim-form
			 (make-proof-in-aconst-form intro-aconst)
			 term))))))
     ((classical-formula=? concl truth)
      (make-proof-in-aconst-form truth-aconst))
     (else
      (myerror "coidpredconst-to-closure-mr-proof-or-intro"
	       "No proof found for" concl
	       "from assumptions"
	       assumptions)))))

(define (coidpredconst-to-closure-mr-proof-or-elim
	 formula gfp-info-or-f . assumptions)
  (cond
   ((all-allnc-form? formula)
    (let* ((vars (all-allnc-form-to-vars formula)))
      (apply mk-proof-in-nc-intro-form
	     (append vars
		     (list (apply coidpredconst-to-closure-mr-proof-or-elim
			    (all-allnc-form-to-final-kernel formula)
			    gfp-info-or-f assumptions))))))
   ((imp-impnc-form? formula)
    (let* ((prems (imp-impnc-form-to-premises formula))
	   (avars (map formula-to-new-avar prems))
	   (concl (imp-impnc-form-to-final-conclusion formula)))
      (apply
       mk-proof-in-nc-intro-form
       (append
	avars
	(list
	 (apply
	  coidpredconst-to-closure-mr-proof-or-elim
	  concl gfp-info-or-f (append assumptions avars)))))))
   ((eqd-form? (avar-to-formula (rac assumptions)))
    (apply coidpredconst-to-closure-mr-proof-or-intro
	   formula gfp-info-or-f assumptions))
   (else
    (let* ((last-prem (avar-to-formula (rac assumptions)))
	   (concl (imp-impnc-form-to-final-conclusion formula))
	   (elim-proof
	    (cond ((ex-form? last-prem)
		   (make-proof-in-aconst-form
		    (ex-formula-and-concl-to-ex-elim-aconst last-prem
							    concl)))
		  ((and-form? last-prem)
		   (and-formula-and-concl-to-and-elim-proof last-prem
							    concl))
		  (else
		   (let ((imp-formula
			  (if (not (term? gfp-info-or-f))
			      (make-imp last-prem concl)
			      (let* ((elim-var
				      (type-to-new-partial-var
				       (term-to-type gfp-info-or-f)))
				     (gen-subst
				      (make-subst
				       gfp-info-or-f
				       (make-term-in-var-form elim-var))))
				(formula-gen-substitute
				 (make-imp last-prem concl)
				 gen-subst)))))
		     (make-proof-in-aconst-form
		      (imp-formulas-to-elim-aconst imp-formula))))))
	   (elim-fla (proof-to-formula elim-proof))
	   (elim-kernel (all-allnc-form-to-final-kernel elim-fla))
	   (elim-prem (imp-impnc-form-to-premise elim-kernel))
	   (elim-concl (imp-impnc-form-to-final-conclusion elim-kernel))
	   (flex-vars (all-allnc-form-to-vars elim-fla))
	   (sig-vars (set-minus (formula-to-free concl) flex-vars))
	   (subst (caar (apply huet-unifiers sig-vars flex-vars '()
			       (list #t (list last-prem elim-prem)
				     (list concl elim-concl)))))
	   (terms
	    (map (lambda (v) (term-substitute (make-term-in-var-form v)
					      subst))
		 flex-vars))
	   (step-formulas
	    (map (lambda (fla) (formula-substitute fla subst))
		 (cdr (imp-impnc-form-to-premises elim-kernel))))
	   (updated-assumptions (rdc assumptions))
	   (step-proofs
	    (cond
	     ((ori-mr-ori-form? last-prem)
	      (map
	       (lambda (fla i)
		 (apply coidpredconst-to-closure-mr-proof-or-elim
			fla gfp-info-or-f (snoc updated-assumptions i)))
	       step-formulas (list 0 1)))
	     ((exi-mr-exi-form? last-prem)
	      (list
	       (apply coidpredconst-to-closure-mr-proof-or-elim
		      (car step-formulas) gfp-info-or-f updated-assumptions)))
	     ((ex-form? last-prem)
	      (list
	       (apply coidpredconst-to-closure-mr-proof-or-elim
		      (car step-formulas) gfp-info-or-f updated-assumptions)))
	     ((or (and-form? last-prem) (andi-mr-andi-form? last-prem))
	      (let*
		  ((step-fla (car step-formulas))
		   (step-vars (all-allnc-form-to-vars step-fla))
		   (step-kernel (all-allnc-form-to-final-kernel step-fla))
		   (step-prems (imp-impnc-all-allnc-form-to-premises step-kernel))
		   (last-step-prem (rac step-prems))
		   (elim-intro-switch? (and (eqd-form? last-step-prem))))
		(list
		 (if
		  elim-intro-switch?
		  (let*
		      ((step-prem-avars (map formula-to-new-avar step-prems))
		       (step-concl (imp-impnc-form-to-final-conclusion step-kernel))
		       (eqd-args (predicate-form-to-args last-step-prem))
		       (lterm (car eqd-args))
		       (rterm (cadr eqd-args))
		       (real-var (term-in-var-form-to-var lterm))
		       (real-subst (make-subst real-var rterm))
		       (compat-proof
			(eqd-compat-rev-at (make-all real-var step-concl)))
		       (compat-prem (formula-substitute step-concl real-subst))
		       (compat-prem-proof
			(apply coidpredconst-to-closure-mr-proof-or-intro
			       (nf compat-prem) gfp-info-or-f
			       (snoc updated-assumptions (car step-prem-avars))))
		       (compat-concl-proof
			(apply
			 mk-proof-in-elim-form
			 compat-proof
			 (append
			  eqd-args
			  (list (make-proof-in-avar-form
				 (cadr step-prem-avars))
				compat-prem-proof)))))
		    (apply mk-proof-in-nc-intro-form
			   (append step-prem-avars
				   (list compat-concl-proof))))
		  (apply coidpredconst-to-closure-mr-proof-or-elim
			 step-fla gfp-info-or-f updated-assumptions)))))
	     (else
	      (apply coidpredconst-to-closure-mr-proof-or-elim
		     last-prem gfp-info-or-f updated-assumptions)))))
      (apply
       mk-proof-in-elim-form
       elim-proof
       (append terms
	       (cons (make-proof-in-avar-form (rac assumptions))
		     step-proofs)))))))

(define (make-avar-or-ga-to-var)
  ;; returns a procedure assigning to assumption variables or
  ;; constants (gas) whose types have computational content new object
  ;; variables of the corresponding et-type.  It remembers the
  ;; assignment done so far.
  (let ((avar-assoc-list '())
	(ga-assoc-list '()))
    (lambda (x)
      (let ((info (if (avar-form? x)
		      (assoc-wrt avar=? x avar-assoc-list)
		      (assoc-wrt aconst=? x ga-assoc-list))))
	(if info
	    (cadr info)
	    (let* ((formula (if (avar-form? x)
				(avar-to-formula x)
				(aconst-to-formula x)))
		   (type (formula-to-et-type formula))
		   (new-var (if (nulltype? type)
				(myerror "make-avar-or-ga-to-var"
					 "computational content expected in"
					 formula)
				(type-to-new-partial-var type))))
	      (if (avar-form? x)
		  (begin (set! avar-assoc-list
			       (cons (list x new-var) avar-assoc-list))
			 new-var)
		  (begin (set! ga-assoc-list
			       (cons (list x new-var) ga-assoc-list))
			 new-var))))))))

(define (make-avar-or-ga-to-mr-avar avar-or-ga-to-var)
  ;; returns a procedure assigning to an avar or ga u:A a new avar
  ;; u':v_u mr A.  Remembers the assignment done so far.
  (let ((avar-assoc-list '())
	(ga-assoc-list '()))
    (lambda (x)
      (let ((info (if (avar-form? x)
		      (assoc-wrt avar=? x avar-assoc-list)
		      (assoc-wrt aconst=? x ga-assoc-list))))
	(if info
	    (cadr info)
	    (let* ((formula (if (avar-form? x)
				(avar-to-formula x)
				(aconst-to-formula x)))
		   (mr-formula (if (formula-of-nulltype? formula)
				   formula
				   (real-and-formula-to-mr-formula-aux
				    (make-term-in-var-form
				     (avar-or-ga-to-var x))
				    formula)))
		   (mr-avar (formula-to-new-avar mr-formula "umr")))
	      (if (avar-form? x)
		  (begin (set! avar-assoc-list
			       (cons (list x mr-avar) avar-assoc-list))
			 mr-avar)
		  (begin (set! ga-assoc-list
			       (cons (list x mr-avar) ga-assoc-list))
			 mr-avar))))))))

(define (proof-to-soundness-proof . opt-proof-or-thm-name)
  (if (null? opt-proof-or-thm-name)
      (proof-to-soundness-proof (current-proof))
      (let* ((proof-or-thm-name (car opt-proof-or-thm-name))
	     (proof (cond ((proof-form? proof-or-thm-name) proof-or-thm-name)
			  ((string? proof-or-thm-name)
			   (theorem-name-to-proof proof-or-thm-name))
			  (else (myerror "proof-to-soundness-proof"
					 "proof or theorem name expected"
					 proof-or-thm-name)))))
	(if (formula-of-nulltype? (proof-to-formula proof))
	    proof
	    (let* ((avar-or-ga-to-var (make-avar-or-ga-to-var))
		   (avar-or-ga-to-mr-avar (make-avar-or-ga-to-mr-avar
					   avar-or-ga-to-var)))
	      (proof-to-soundness-proof-aux
	       proof avar-or-ga-to-var avar-or-ga-to-mr-avar))))))

(define (proof-to-soundness-proof-aux
	 proof avar-or-ga-to-var avar-or-ga-to-mr-avar)
  (cond
   ((proof-in-avar-form? proof)
    (let ((avar (proof-in-avar-form-to-avar proof)))
      (if (not (formula-of-nulltype? (proof-to-formula proof)))
	  (make-proof-in-avar-form (avar-or-ga-to-mr-avar avar))
	  proof)))
   ((proof-in-aconst-form? proof)
    (let ((aconst (proof-in-aconst-form-to-aconst proof)))
      (case (aconst-to-kind aconst)
	((axiom) (if (not (formula-of-nulltype? (proof-to-formula proof)))
		     (axiom-to-soundness-proof aconst)
		     proof))
	((theorem) (if (not (formula-of-nulltype? (proof-to-formula proof)))
		       (theorem-to-soundness-proof aconst)
		       proof))
	((global-assumption) (global-assumption-to-soundness-proof
			      aconst avar-or-ga-to-mr-avar))
	(else (myerror
	       "proof-to-soundness-proof-aux" "unknown kind of aconst"
	       (aconst-to-kind aconst))))))
   ((and (proof-in-imp-intro-form? proof)
	 (not (formula-of-nulltype? (proof-to-formula proof))))
    (let* ((avar (proof-in-imp-intro-form-to-avar proof))
	   (kernel (proof-in-imp-intro-form-to-kernel proof))
	   (avar-fla (avar-to-formula avar))
	   (kernel-proof (proof-to-soundness-proof-aux
			  kernel avar-or-ga-to-var avar-or-ga-to-mr-avar)))
      (if (not (formula-of-nulltype? avar-fla))
	  (let ((mr-avar (avar-or-ga-to-mr-avar avar)))
	    (mk-proof-in-intro-form
	     (avar-or-ga-to-var avar) mr-avar kernel-proof))
	  (mk-proof-in-intro-form avar kernel-proof))))
   ((or (proof-in-imp-intro-form? proof) ;then formula is n.c.
	(proof-in-impnc-intro-form? proof))
    (let* ((avar (if (proof-in-imp-intro-form? proof)
		     (proof-in-imp-intro-form-to-avar proof)
		     (proof-in-impnc-intro-form-to-avar proof)))
	   (kernel (if (proof-in-imp-intro-form? proof)
		       (proof-in-imp-intro-form-to-kernel proof)
		       (proof-in-impnc-intro-form-to-kernel proof)))
	   (avar-fla (avar-to-formula avar))
	   (kernel-proof (proof-to-soundness-proof-aux
			  kernel avar-or-ga-to-var avar-or-ga-to-mr-avar)))
      (if (not (formula-of-nulltype? avar-fla))
	  (let* ((var (avar-or-ga-to-var avar))
		 (mr-avar (avar-or-ga-to-mr-avar avar))
		 (mr-avar-fla (avar-to-formula mr-avar))
		 (exl-fla (make-exl var mr-avar-fla))
		 (kernel-fla (proof-to-formula kernel-proof))
		 (imp-fla (make-imp exl-fla kernel-fla))
		 (free (formula-to-free imp-fla))
		 (elim-aconst (imp-formulas-to-elim-aconst imp-fla))
		 (exl-proof
		  (apply mk-proof-in-elim-form
			 (make-proof-in-aconst-form
			  (formula-to-invarex-aconst avar-fla))
			 (append (map make-term-in-var-form
				      (formula-to-free avar-fla))
				 (list (make-proof-in-avar-form avar)))))
		 (ih-proof
		  (mk-proof-in-intro-form var mr-avar kernel-proof)))
	    (mk-proof-in-intro-form
	     avar (apply mk-proof-in-elim-form
			 (make-proof-in-aconst-form elim-aconst)
			 (append (map make-term-in-var-form free)
				 (list exl-proof ih-proof)))))
	  (mk-proof-in-intro-form avar kernel-proof))))
   ((and (proof-in-imp-elim-form? proof)
	 (not (formula-of-nulltype? (proof-to-formula proof))))
    (let* ((op (proof-in-imp-elim-form-to-op proof))
	   (arg (proof-in-imp-elim-form-to-arg proof))
	   (arg-fla (proof-to-formula arg))
	   (op-proof (proof-to-soundness-proof-aux
		      op avar-or-ga-to-var avar-or-ga-to-mr-avar))
	   (arg-proof (proof-to-soundness-proof-aux
		       arg avar-or-ga-to-var avar-or-ga-to-mr-avar)))
      (if (not (formula-of-nulltype? arg-fla))
	  (mk-proof-in-elim-form
	   op-proof
	   (proof-to-extracted-term-aux
	    arg avar-or-ga-to-var #t) ;unfold-let-flag is true here
	   arg-proof)
	  (mk-proof-in-elim-form op-proof arg-proof))))
   ((or (proof-in-imp-elim-form? proof) ;then formula is n.c.
	(proof-in-impnc-elim-form? proof))
    (let* ((op (if (proof-in-imp-elim-form? proof)
		   (proof-in-imp-elim-form-to-op proof)
		   (proof-in-impnc-elim-form-to-op proof)))
	   (arg (if (proof-in-imp-elim-form? proof)
		    (proof-in-imp-elim-form-to-arg proof)
		    (proof-in-impnc-elim-form-to-arg proof)))
	   (arg-fla (proof-to-formula arg))
	   (op-proof (proof-to-soundness-proof-aux
		      op avar-or-ga-to-var avar-or-ga-to-mr-avar))
	   (arg-proof (proof-to-soundness-proof-aux
		       arg avar-or-ga-to-var avar-or-ga-to-mr-avar)))
      (if (not (formula-of-nulltype? arg-fla))
	  (let ((elim-proof
		 (apply
		  mk-proof-in-elim-form
		  (make-proof-in-aconst-form
		   (formula-to-invarall-aconst arg-fla))
		  (append
		   (map make-term-in-var-form (formula-to-free arg-fla))
		   (list
		    (proof-to-extracted-term-aux
		     arg avar-or-ga-to-var #t) ;unfold-let-flag is true here
		    arg-proof)))))
	    (mk-proof-in-elim-form op-proof elim-proof))
	  (mk-proof-in-elim-form op-proof arg-proof))))
   ((proof-in-and-intro-form? proof)
    (let* ((left (proof-in-and-intro-form-to-left proof))
	   (right (proof-in-and-intro-form-to-right proof))
	   (left-proof (proof-to-soundness-proof-aux
			left avar-or-ga-to-var avar-or-ga-to-mr-avar))
	   (right-proof (proof-to-soundness-proof-aux
			 right avar-or-ga-to-var avar-or-ga-to-mr-avar)))
      (make-proof-in-and-intro-form left-proof right-proof)))
   ((proof-in-and-elim-left-form? proof)
    (let* ((kernel (proof-in-and-elim-left-form-to-kernel proof))
	   (kernel-proof (proof-to-soundness-proof-aux
			  kernel avar-or-ga-to-var avar-or-ga-to-mr-avar)))
      (make-proof-in-and-elim-left-form kernel-proof)))
   ((proof-in-and-elim-right-form? proof)
    (let* ((kernel (proof-in-and-elim-right-form-to-kernel proof))
	   (kernel-proof (proof-to-soundness-proof-aux
			  kernel avar-or-ga-to-var avar-or-ga-to-mr-avar)))
      (make-proof-in-and-elim-right-form kernel-proof)))
   ((proof-in-all-intro-form? proof)
    (let* ((var (proof-in-all-intro-form-to-var proof))
	   (kernel (proof-in-all-intro-form-to-kernel proof))
	   (kernel-proof (proof-to-soundness-proof-aux
			  kernel avar-or-ga-to-var avar-or-ga-to-mr-avar)))
      (mk-proof-in-intro-form var kernel-proof)))
   ((proof-in-all-elim-form? proof)
    (let* ((op (proof-in-all-elim-form-to-op proof))
	   (op-proof (proof-to-soundness-proof-aux
		      op avar-or-ga-to-var avar-or-ga-to-mr-avar))
	   (arg (proof-in-all-elim-form-to-arg proof)))
      (mk-proof-in-elim-form op-proof arg)))
   ((proof-in-allnc-intro-form? proof)
    (let* ((var (proof-in-allnc-intro-form-to-var proof))
	   (kernel (proof-in-allnc-intro-form-to-kernel proof))
	   (kernel-proof (proof-to-soundness-proof-aux
			  kernel avar-or-ga-to-var avar-or-ga-to-mr-avar)))
      (mk-proof-in-intro-form var kernel-proof)))
   ((proof-in-allnc-elim-form? proof)
    (let* ((op (proof-in-allnc-elim-form-to-op proof))
	   (op-proof (proof-to-soundness-proof-aux
		      op avar-or-ga-to-var avar-or-ga-to-mr-avar))
	   (arg (proof-in-allnc-elim-form-to-arg proof)))
      (mk-proof-in-elim-form op-proof arg)))
   (else (myerror "proof-to-soundness-proof-aux"
		  "unexpected proof with tag" (tag proof)))))

(define alltotal-intro-mr-aconst
  (let* ((formula-of-alltotal-intro-aconst
	  (aconst-to-uninst-formula alltotal-intro-aconst))
	 (id-eterm (proof-to-extracted-term
		    (make-proof-in-aconst-form alltotal-intro-aconst)))
	 (formula-of-alltotal-intro-mr-aconst
	  (real-and-formula-to-mr-formula
	   id-eterm formula-of-alltotal-intro-aconst)))
    (make-aconst "AllTotalIntroSound"
		 'axiom formula-of-alltotal-intro-mr-aconst empty-subst)))

(define alltotal-elim-mr-aconst
  (let* ((formula-of-alltotal-elim-aconst
	  (aconst-to-uninst-formula alltotal-elim-aconst))
	 (id-eterm (proof-to-extracted-term
		    (make-proof-in-aconst-form alltotal-elim-aconst)))
	 (formula-of-alltotal-elim-mr-aconst
	  (real-and-formula-to-mr-formula
	   id-eterm formula-of-alltotal-elim-aconst)))
    (make-aconst "AllTotalElimSound"
		 'axiom formula-of-alltotal-elim-mr-aconst empty-subst)))

(define allnctotal-intro-mr-aconst
  (let* ((formula-of-allnctotal-intro-aconst
	  (aconst-to-uninst-formula allnctotal-intro-aconst))
	 (id-eterm (proof-to-extracted-term
		    (make-proof-in-aconst-form allnctotal-intro-aconst)))
	 (formula-of-allnctotal-intro-mr-aconst
	  (real-and-formula-to-mr-formula
	   id-eterm formula-of-allnctotal-intro-aconst)))
    (make-aconst "AllncTotalIntroSound"
		 'axiom formula-of-allnctotal-intro-mr-aconst empty-subst)))

(define allnctotal-elim-mr-aconst
  (let* ((formula-of-allnctotal-elim-aconst
	  (aconst-to-uninst-formula allnctotal-elim-aconst))
	 (id-eterm (proof-to-extracted-term
		    (make-proof-in-aconst-form allnctotal-elim-aconst)))
	 (formula-of-allnctotal-elim-mr-aconst
	  (real-and-formula-to-mr-formula
	   id-eterm formula-of-allnctotal-elim-aconst)))
    (make-aconst "AllncTotalElimSound"
		 'axiom formula-of-allnctotal-elim-mr-aconst empty-subst)))

(define (axiom-to-soundness-proof aconst)
  (let ((name (aconst-to-name aconst)))
    (cond
     ((string=? "Ind" name)
      (apply all-formulas-to-mr-ind-proof (aconst-to-repro-data aconst)))
     ((string=? "Cases" name)
      (all-formula-to-mr-cases-proof (car (aconst-to-repro-data aconst))))
     ((string=? "GInd" name) (gind-aconst-to-mr-gind-proof aconst))
     ((string=? "Intro" name)
      (let* ((repro-data (aconst-to-repro-data aconst))
	     (number (car repro-data))
	     (idpc (cadr repro-data)))
	(number-and-idpredconst-to-intro-mr-proof number idpc)))
     ((string=? "Elim" name)
      (let* ((imp-formulas (aconst-to-repro-data aconst))
	     (imp-formula (car imp-formulas))
	     (prem (imp-form-to-premise imp-formula))
	     (concl (imp-form-to-conclusion imp-formula))
	     (idpc (predicate-form-to-predicate prem))
	     (idpc-name (idpredconst-to-name idpc)))
	(cond ;extra treatment for ExL, ExR, ExLT, ExRT, AndL, AndR
					;EqD, ExU, ExUT, AndU, to avoid Rec
	 ((member idpc-name '("ExL" "ExLT"))
	  (let* ((cterms (idpredconst-to-cterms idpc))
		 (cterm (car cterms))
		 (exl-formula (make-exl (car (cterm-to-vars cterm))
					(cterm-to-formula cterm))))
	    (imp-formulas-to-mr-elim-proof (make-imp exl-formula concl))))
	 ;; Code discarded 2016-06-27
	 ;; (exl-formula-and-concl-to-exl-elim-mr-proof exl-formula concl)))
	 ((member idpc-name '("ExR" "ExRT"))
	  (let* ((cterms (idpredconst-to-cterms idpc))
		 (cterm (car cterms))
		 (exr-formula (make-exr (car (cterm-to-vars cterm))
					(cterm-to-formula cterm))))
	    (imp-formulas-to-mr-elim-proof (make-imp exr-formula concl))))
	 ((member idpc-name '("AndL" "AndR"))
	  (let* ((cterms (idpredconst-to-cterms idpc))
		 (left-cterm (car cterms))
		 (right-cterm (cadr cterms))
		 (left (cterm-to-formula left-cterm))
		 (right (cterm-to-formula right-cterm))
		 (andlr-formula (if (string=? "AndL" idpc-name)
				    (make-andl left right)
				    (make-andr left right))))
	    (andlr-formula-and-concl-to-andlr-elim-mr-proof
	     andlr-formula concl)))
	 ((string=? "EqD" idpc-name)
	  (one-clause-nc-idpc-formula-and-concl-to-elim-mr-proof
	   prem concl))
	 ;; ((string=? "EqD" idpc-name)
	 ;;  (eqd-elim-aconst-to-eqd-mr-elim-proof aconst))
	 ((member idpc-name '("ExU" "ExUT"))
	  (let* ((cterms (idpredconst-to-cterms idpc))
		 (cterm (car cterms))
		 (exu-formula (make-exu (car (cterm-to-vars cterm))
					(cterm-to-formula cterm))))
	    (one-clause-nc-idpc-formula-and-concl-to-elim-mr-proof
	     exu-formula concl)))
	 ((string=? "AndU" idpc-name)
	  (let* ((cterms (idpredconst-to-cterms idpc))
		 (cterm1 (car cterms))
		 (cterm2 (cadr cterms))
		 (andu-formula
		  (make-andu (cterm-to-formula cterm1)
			     (cterm-to-formula cterm2))))
	    (one-clause-nc-idpc-formula-and-concl-to-elim-mr-proof
	     andu-formula concl)))
	 (else (apply imp-formulas-to-mr-elim-proof imp-formulas)))))
     ((string=? "Closure" name)
      (let ((coidpc (predicate-form-to-predicate
		     (imp-form-to-premise
		      (allnc-form-to-final-kernel
		       (aconst-to-formula aconst))))))
	(coidpredconst-to-closure-mr-proof coidpc)))
     ((string=? "Gfp" name)
      (apply imp-formulas-to-mr-gfp-proof (aconst-to-repro-data aconst)))
     ((string=? "Ex-Intro" name)
      (ex-formula-to-ex-intro-mr-proof
       (car (aconst-to-repro-data aconst))))
     ((string=? "Ex-Elim" name)
      (apply ex-formula-and-concl-to-ex-elim-mr-proof
	     (aconst-to-repro-data aconst)))
     ((member name (list "AllTotalIntro" "AllTotalElim"
			 "AllncTotalIntro" "AllncTotalElim"
			 ;; "MRIntro" "MRElim"
			 ;; "ExDTotalIntro" "ExDTotalElim"
			 ;; "ExLTotalIntro" "ExLTotalElim"
			 ;; "ExRTotalIntro" "ExRTotalElim"
			 "ExTotalIntro" "ExTotalElim"))
      (let* ((tpsubst (aconst-to-tpsubst aconst))
	     (uninst-formula (aconst-to-uninst-formula aconst))
	     (final-concl
	      (imp-impnc-all-allnc-form-to-final-conclusion uninst-formula))
	     (final-atom ;P x^
	      (if (string=? "ExTotalIntro" name)
		  (ex-form-to-kernel final-concl)
		  final-concl))
	     (pvar (predicate-form-to-predicate final-atom)) ;P
	     (args (predicate-form-to-args final-atom)) ;(x^)
	     (pvar-tvar (PVAR-TO-TVAR pvar))
	     (tvar (term-to-type (car args))) ;alpha
	     (type (let ((info (assoc tvar tpsubst))) ;rho
	     	     (if info (cadr info) tvar)))
	     (cterm (let ((info (assoc pvar tpsubst))) ;{n^|A(n^)}
		      (if info (cadr info) (predicate-to-cterm pvar))))
	     (cterm-var (car (cterm-to-vars cterm))) ;n^
	     (cterm-fla (cterm-to-formula cterm)) ;A(n^)
	     (cterm-type (formula-to-et-type cterm-fla))
	     (new-tsubst (make-substitution (list tvar pvar-tvar)
					    (list type cterm-type)))
	     (var (type-to-new-partial-var cterm-type)) ;u^
	     (mr-cterm-fla ;u^ mr A(n^)
	      (real-and-formula-to-mr-formula
	       (make-term-in-var-form var) cterm-fla))
	     (mr-cterm ;{u^,n^|u^ mr A(n^)}
	      (make-cterm var cterm-var mr-cterm-fla))
	     (mr-pvar (PVAR-TO-MR-PVAR pvar))
	     (new-psubst (make-subst-wrt pvar-cterm-equal? mr-pvar mr-cterm))
	     (new-aconst
	      (cond
	       ((string=? name "AllTotalIntro")	alltotal-intro-mr-aconst)
	       ((string=? name "AllTotalElim") alltotal-elim-mr-aconst)
	       ((string=? name "AllncTotalIntro") allnctotal-intro-mr-aconst)
	       ((string=? name "AllncTotalElim") allnctotal-elim-mr-aconst)
	       ((string=? name "ExTotalIntro") extotal-intro-mr-aconst)
	       ((string=? name "ExTotalElim") extotal-elim-mr-aconst))))
	(make-proof-in-aconst-form
	 (make-aconst (string-append name "Sound")
		      'axiom
		      (aconst-to-uninst-formula new-aconst)
		      (append new-tsubst new-psubst)))))
     ((string=? "InhabTotal" name) ;obsolete
      (let* ((formula (aconst-to-formula aconst))
	     (arg (car (predicate-form-to-args formula)))
	     (type (term-to-type arg)))
	(type-to-inhabtotal-mr-proof type)))
     ((string=? "InhabTotalMR" name) ;obsolete
      (make-proof-in-aconst-form aconst))
     (else (myerror "axiom-to-soundness-proof" "unexpected axiom" name)))))

(define (theorem-to-soundness-proof aconst)
  (let* ((thm-name (aconst-to-name aconst))
	 (tpsubst (aconst-to-tpsubst aconst))
	 (tsubst (list-transform-positive tpsubst
		   (lambda (x) (tvar-form? (car x)))))
	 (psubst (list-transform-positive tpsubst
		   (lambda (x) (pvar-form? (car x))))))
    (cond
     ((string=? "Id" thm-name)
      (let* ((pvar (predicate-form-to-predicate
		    (imp-impnc-all-allnc-form-to-final-conclusion
		     (aconst-to-uninst-formula aconst))))
	     (cterm (let ((info (assoc pvar psubst)))
		      (if info
			  (cadr info)
			  (predicate-to-cterm pvar))))
	     (cterm-formula (cterm-to-formula cterm))
	     (et-type (formula-to-et-type cterm-formula))
	     (mr-var (type-to-new-partial-var et-type))
	     (mr-formula (real-and-formula-to-mr-formula
			  (make-term-in-var-form mr-var) cterm-formula))	
	     (mr-cterm (make-cterm mr-formula))
	     (mr-tpsubst (append tsubst (list (list pvar mr-cterm))))
	     (orig-aconst (theorem-name-to-aconst thm-name))
	     (mr-aconst (aconst-substitute orig-aconst mr-tpsubst))
					;all xs(a mr A -> a mr A)
	     (mr-aconst-formula (aconst-to-formula mr-aconst))
	     (vars (all-allnc-form-to-vars mr-aconst-formula)))
	(if (equal? vars (append (remove mr-var vars) (list mr-var)))
	    (make-proof-in-aconst-form mr-aconst)
	    (let ((elim-proof
		   (apply
		    mk-proof-in-elim-form
		    (make-proof-in-aconst-form mr-aconst)
		    (map make-term-in-var-form vars))))
	      (apply mk-proof-in-intro-form
		     (append (remove mr-var vars)
			     (list mr-var elim-proof)))))))
     ((member thm-name (list "EqDCompatRev" "EqDCompat"))
      (let* ((pvar (predicate-form-to-predicate
		    (imp-impnc-all-allnc-form-to-final-conclusion
		     (aconst-to-uninst-formula aconst))))
	     (cterm (let ((info (assoc pvar psubst)))
		      (if info
			  (cadr info)
			  (predicate-to-cterm pvar))))
	     (cterm-vars (cterm-to-vars cterm))
	     (cterm-formula (cterm-to-formula cterm))
	     (et-type (formula-to-et-type cterm-formula))
	     (mr-var (type-to-new-partial-var et-type))
	     (mr-formula (real-and-formula-to-mr-formula
			  (make-term-in-var-form mr-var) cterm-formula))
	     (mr-cterm
	      (apply make-cterm (append cterm-vars (list mr-formula))))
	     (mr-tpsubst (append tsubst (list (list pvar mr-cterm))))
	     (orig-aconst (theorem-name-to-aconst thm-name))
	     (mr-aconst (aconst-substitute orig-aconst mr-tpsubst))
					;all xs,n,m(n=m -> a mr A(m) ->
					;a mr A(n)) or conversely
	     (mr-aconst-formula (aconst-to-formula mr-aconst))
	     (vars (all-allnc-form-to-vars mr-aconst-formula))
	     (eqd-hyp ;n=m
	      (car (imp-impnc-form-to-premises
		    (all-allnc-form-to-final-kernel mr-aconst-formula))))
	     (u (formula-to-new-avar eqd-hyp))
	     (elim-proof
	      (apply mk-proof-in-elim-form
		     (make-proof-in-aconst-form mr-aconst)
		     (append (map make-term-in-var-form vars)
			     (list (make-proof-in-avar-form u))))))
	(apply mk-proof-in-intro-form
	       (append (remove mr-var vars)
		       (list u mr-var elim-proof)))))
     (else
      (let ((info (assoc (string-append thm-name "Sound") THEOREMS)))
	(if
	 info ;ThmSound exists
	 (let* ((sname (string-append thm-name "Sound"))
		(mr-aconst (theorem-name-to-aconst sname))
		(mr-proof (theorem-name-to-proof sname))
		(uninst-formula (aconst-to-uninst-formula aconst))
		(pvars (formula-to-pvars uninst-formula))
		(mr-pvars (map PVAR-TO-MR-PVAR pvars))
		(tvars (map PVAR-TO-TVAR pvars))
		(cterms (map (lambda (pvar)
			       (let ((info (assoc pvar psubst)))
				 (if info
				     (cadr info)
				     (predicate-to-cterm pvar))))
			     pvars))
		(cterm-varss (map cterm-to-vars cterms))
		(cterm-formulas (map cterm-to-formula cterms))
		(et-types (map formula-to-et-type cterm-formulas))
		(mr-vars (map type-to-new-partial-var et-types))
		(mr-formulas
		 (map (lambda (mr-var cterm-fla)
			(real-and-formula-to-mr-formula
			 (make-term-in-var-form mr-var) cterm-fla))
		      mr-vars cterm-formulas))
		(mr-cterms
		 (map (lambda (mr-var cterm-vars mr-fla)
			(apply make-cterm
			       mr-var (append cterm-vars (list mr-fla))))
		      mr-vars cterm-varss mr-formulas))
		(mr-psubst (make-substitution-wrt
			    pvar-cterm-equal? mr-pvars mr-cterms))
		(mr-tsubst (make-substitution tvars et-types))
		(subst-mr-aconst
		 (aconst-substitute
		  mr-aconst (append tsubst mr-tsubst psubst mr-psubst))))
	   (make-proof-in-aconst-form subst-mr-aconst))
	 (let* ((inst-proof (theorem-aconst-to-inst-proof aconst))
		(free (formula-to-free (proof-to-formula inst-proof)))
		(closed-inst-proof
		 (apply mk-proof-in-intro-form
			(append free (list inst-proof)))))
	   (comment "proof-to-soundness-proof : recursive call at "
		    (aconst-to-name aconst))
	   (proof-to-soundness-proof closed-inst-proof))))))))

(define (global-assumption-to-soundness-proof aconst avar-or-ga-to-mr-avar)
  (let* ((name (aconst-to-name aconst))
	 (info (assoc name GLOBAL-ASSUMPTIONS)))
    (if info
	(if (or (string=? "Efq" name) (string=? "EfqLog" name))
	    (efq-ga-to-mr-efq-ga-proof aconst)
	    (let ((mr-avar (avar-or-ga-to-mr-avar aconst)))
	      (make-proof-in-avar-form mr-avar)))
	(myerror "global-assumption-to-soundness-proof"
		 "global assumption expected" name))))

(define (proof-to-soundness-formula proof)
  (real-and-formula-to-mr-formula
   (proof-to-extracted-term proof)
   (proof-to-formula proof)))

(set! COMMENT-FLAG #f)

;; TotalVar
(set-goal "all alpha Total alpha")
(use "AllTotalIntro")
(assume "alpha^" "Tx")
(use "Tx")
;; Proof finished
(save "TotalVar")

;; (pp (rename-variables (nt (proof-to-extracted-term))))
;; [alpha]alpha

(define sproof (proof-to-soundness-proof (current-proof)))

;; TotalVarSound
(set-goal (rename-variables (nf (proof-to-formula sproof))))
(use sproof)
;; Proof finished.
(save "TotalVarSound")

;; ExDTotalElim
(set-goal "exd alpha (Pvar alpha)alpha -> 
           exr alpha^(Total alpha^ andd (Pvar alpha)alpha^)")
(assume "ExHyp")
(by-assume "ExHyp" "alpha" "alphaProp")
(intro 0 (pt "alpha"))
(split)
(use "TotalVar")
(use "alphaProp")
;; Proof finished.
(save "ExDTotalElim")

;; (pp (rename-variables (nt (proof-to-extracted-term))))
;; [(alpha yprod gamma)](alpha yprod gamma)

(define sproof (proof-to-soundness-proof (current-proof)))

;; ExDTotalElimSound
(set-goal (rename-variables (nf (proof-to-formula sproof))))
(use-with sproof)
;; Proof finished.
(save "ExDTotalElimSound")

;; ExLTotalElim
(set-goal "exl alpha (Pvar alpha)^ alpha -> 
           exr alpha^(Total alpha^ andl (Pvar alpha)^ alpha^)")
(assume "ExHyp")
(by-assume "ExHyp" "alpha" "alphaProp")
(intro 0 (pt "alpha"))
(split)
(use "TotalVar")
(use "alphaProp")
;; Proof finished.
(save "ExLTotalElim")

;; (pp (rename-variables (nt (proof-to-extracted-term))))
;; [alpha]alpha

(define sproof (proof-to-soundness-proof (current-proof)))

;; ExLTotalElimSound
(set-goal (rename-variables (nf (proof-to-formula sproof))))
(use-with sproof)
;; Proof finished.
(save "ExLTotalElimSound")

;; ExRTotalElim
(set-goal "exr alpha (Pvar alpha)alpha -> 
           exr alpha^(TotalMR alpha^ alpha^ andr (Pvar alpha)alpha^)")
(assume "ExHyp")
(by-assume "ExHyp" "alpha" "alphaProp")
(intro 0 (pt "alpha"))
(split)
(use "TotalMRIntro")
(use "alphaProp")
;; Proof finished.
(save "ExRTotalElim")

;; (pp (rename-variables (nt (proof-to-extracted-term))))
;; [gamma]gamma

(define sproof (proof-to-soundness-proof (current-proof)))

;; ExRTotalElimSound
(set-goal (rename-variables (nf (proof-to-formula sproof))))
(use-with sproof)
;; Proof finished.
(save "ExRTotalElimSound")

;; ExUTotalElim
(set-goal "exu alpha (Pvar alpha)alpha -> 
           exu alpha^(Total alpha^ andu (Pvar alpha)alpha^)")
(assume "ExHyp")
(by-assume "ExHyp" "alpha" "alphaProp")
(intro 0 (pt "alpha"))
(split)
(use "TotalVar")
(use "alphaProp")
;; Proof finished.
(save "ExUTotalElim")

;; AllTotalIntroSound
(set-goal "all (alpha=>gamma)^(
 all alpha^0,alpha^1(
  TotalMR alpha^1 alpha^0 -> 
  (Pvar gamma alpha)^((alpha=>gamma)^ alpha^1)alpha^0) -> 
 all alpha_0 (Pvar gamma alpha)^((alpha=>gamma)^ alpha_0)alpha_0)")
(assume "(alpha=>gamma)^" "AllHyp" "alpha")
(use "AllHyp")
(use "TotalMRIntro")
;; Proof finished.
(save "AllTotalIntroSound")

;; AllTotalElimSound
(set-goal "all (alpha=>gamma)^(
 all alpha_0 (Pvar gamma alpha)^((alpha=>gamma)^ alpha_0)alpha_0 -> 
 all alpha^0,alpha^1(
  TotalMR alpha^1 alpha^0 -> 
  (Pvar gamma alpha)^((alpha=>gamma)^ alpha^1)alpha^0))")
(assume "(alpha=>gamma)^" "AllHyp")
(assert "allnc alpha^0(Total alpha^0 -> 
                       (Pvar gamma alpha)^((alpha=>gamma)^ alpha^0)alpha^0)")
 (use "AllTotalElim" )
 (use "AllHyp")
 (drop "AllHyp")
(assume "AllncHyp" "alpha^0"  "alpha^1" "TMRHyp")
(assert "alpha^1 eqd alpha^0")
 (use "TotalMRToEq")
 (use "TMRHyp")
(assume "alpha^1 eqd alpha^0")
(simp "alpha^1 eqd alpha^0")
(use "AllncHyp")
(use "TotalMRToTotal" (pt "alpha^1"))
(use "TMRHyp")
;; Proof finished.
(save "AllTotalElimSound")

;; AllncTotalIntroSound
(set-goal "all gamma^(
 all alpha^0(Total alpha^0 -> (Pvar gamma alpha)^ gamma^ alpha^0) -> 
 all alpha_0 (Pvar gamma alpha)^ gamma^ alpha_0)")
(assume "gamma^" "AllHyp" "alpha")
(use "AllHyp")
(use "TotalVar")
;; Proof finished.
(save "AllncTotalIntroSound")

;; AllncTotalElimSound
(set-goal "all gamma^(
 all alpha_0 (Pvar gamma alpha)^ gamma^ alpha_0 -> 
 all alpha^0(Total alpha^0 -> (Pvar gamma alpha)^ gamma^ alpha^0))")
(assume "gamma^" "AllHyp")
(use-with "AllTotalElim"
	  (make-cterm (pv "alpha^") (pf "(Pvar gamma alpha)^ gamma^ alpha^"))
	  "?")
(use "AllHyp")
;; Proof finished.
(save "AllncTotalElimSound")

;; ExDMRIntro is exactly InitExDMR.  The converse is proved via elim:

;; ExDMRElim
(set-goal "all (alpha yprod gamma)^(
     (ExDMR (cterm (gamma^,alpha^) (Pvar gamma alpha)^ gamma^ alpha^))
     (alpha yprod gamma)^ -> 
     (Pvar gamma alpha)^(rht(alpha yprod gamma)^)
     (lft(alpha yprod gamma)^))")
(assume "(alpha yprod gamma)^" "ExDMRHyp")
(elim "ExDMRHyp")
(ng)
(assume "alpha^" "gamma^" "Hyp")
(use "Hyp")
;; Proof finished.
(save "ExDMRElim")

;; ExLMRIntro is exactly InitExLMR.  The converse is proved via elim:

;; ExLMRElim
(set-goal "all alpha^((ExLMR (cterm (alpha^) (Pvar alpha)^ alpha^))alpha^ ->
 (Pvar alpha)^ alpha^)")
(assume "alpha^" "ExLMRHyp")
(elim "ExLMRHyp")
(assume "alpha^1" "Palpha1")
(use "Palpha1")
;; Proof finished.
(save "ExLMRElim")

;; ExRMRIntro is exactly InitExRMR.  The converse is proved via elim:

;; ExRMRElim
(set-goal "all gamma^,alpha^((ExRMR gamma
  alpha
  (cterm (gamma^0,alpha^1) (Pvar gamma alpha)^ gamma^0 alpha^1))
  gamma^ ->
  exu alpha^ (Pvar gamma alpha)^ gamma^ alpha^)")
(assume "gamma^" "alpha^" "ExRMRHyp")
(elim "ExRMRHyp")
(assume "alpha^1" "gamma^1" "PHyp")
(intro 0 (pt "alpha^1"))
(use "PHyp")
;; Proof finished.
(save "ExRMRElim")

;; Same for ExDT ExLT ExRT

;; ExDTMRElim
(set-goal "all (alpha yprod gamma)^(
     (ExDTMR (cterm (gamma^,alpha) (Pvar gamma alpha)^ gamma^ alpha))
     (alpha yprod gamma)^ -> 
     (Pvar gamma alpha)^(rht(alpha yprod gamma)^)
     (lft(alpha yprod gamma)^))")
(assume "(alpha yprod gamma)^" "ExDTMRHyp")
(elim "ExDTMRHyp")
(ng)
(assume "alpha" "gamma^" "Hyp")
(use "Hyp")
;; Proof finished.
(save "ExDTMRElim")

;; ExLTMRElim
(set-goal "all alpha((ExLTMR (cterm (alpha) (Pvar alpha)^ alpha))alpha ->
 (Pvar alpha)^ alpha)")
(assume "alpha" "ExLTMRHyp")
(elim "ExLTMRHyp")
(assume "alpha_1" "Palpha1")
(use "Palpha1")
;; Proof finished.
(save "ExLTMRElim")

;; ExRTMRElim
(set-goal "all gamma^,alpha((ExRTMR gamma
  alpha
  (cterm (gamma^0,alpha_1) (Pvar gamma alpha)^ gamma^0 alpha_1))
  gamma^ ->
  exu alpha (Pvar gamma alpha)^ gamma^ alpha)")
(assume "gamma^" "alpha" "ExRTMRHyp")
(elim "ExRTMRHyp")
(assume "alpha_1" "gamma^1" "PHyp")
(intro 0 (pt "alpha_1"))
(use "PHyp")
;; Proof finished.
(save "ExRTMRElim")

;; Same for conjunction

;; AndDMRIntro is exactly InitAndDMR.  The converse is proved via elim:

;; AndDMRElim
(set-goal "all (beta1 yprod beta2)^
  ((AndDMR (cterm (beta1^1) (Pvar beta1)^ beta1^1)
    (cterm (beta2^1) (Pvar beta2)^ beta2^1))
  (beta1 yprod beta2)^ ->
  (Pvar beta1)^(lft (beta1 yprod beta2)^) andu
  (Pvar beta2)^(rht (beta1 yprod beta2)^))")
(assume "(beta1 yprod beta2)^" "AndDMRHyp")
(elim "AndDMRHyp")
(ng)
(assume "beta1^" "Hyp1" "beta2^" "Hyp2")
(split)
(use "Hyp1")
(use "Hyp2")
;; Proof finished.
(save "AndDMRElim")

;; AndLMRElimLeft
(set-goal "all beta1^(
 (AndLMR (cterm (beta1^0) (Pvar beta1)^1 beta1^0) (cterm () Pvar2))beta1^ ->
 (Pvar beta1)^1 beta1^)")
(assume "beta1^" "AndLMRHyp")
(elim "AndLMRHyp")
(assume "beta1^1" "Hyp1" "Hyp2")
(use "Hyp1")
;; Proof finished.
(save "AndDMRElimLeft")

;; AndLMRElimRight
(set-goal "all beta1^(
 (AndLMR (cterm (beta1^0) (Pvar beta1)^1 beta1^0) (cterm () Pvar^2))beta1^ ->
 Pvar^2)")
(assume "beta1^" "AndLMRHyp")
(elim "AndLMRHyp")
(assume "beta1^1" "Hyp1" "Hyp2")
(use "Hyp2")
;; Proof finished.
(save "AndDMRElimdRight")

;; OrDMRElim
(set-goal "allnc (beta1 ysum beta2)^(
 (OrDMR (cterm (beta1^0) (Pvar beta1)^1 beta1^0)
   (cterm (beta2^0) (Pvar beta2)^2 beta2^0))(beta1 ysum beta2)^ ->
 all beta1^((Pvar beta1)^1 beta1^ -> Pvar^) -> 
 all beta2^((Pvar beta2)^2 beta2^ -> Pvar^) -> Pvar^)")
(assume "(beta1 ysum beta2)^" "OrDMRHyp")
(elim "OrDMRHyp")
;; 3,4
(assume "beta1^" "PHyp" "Hyp1" "Hyp2")
(use-with "Hyp1" (pt "beta1^") "PHyp")
;; 4
(assume "beta2^" "PHyp" "Hyp1" "Hyp2")
(use-with "Hyp2" (pt "beta2^") "PHyp")
;; Proof finished.
(save "OrDMRElim")

;; OrLMRElim
(set-goal "all (beta1 ysumu)^(
 (OrLMR (cterm (beta1^0) (Pvar beta1)^1 beta1^0) (cterm () Pvar2))
 (beta1 ysumu)^ ->
 all beta1^((Pvar beta1)^1 beta1^ -> Pvar^) -> (Pvar2 -> Pvar^) -> Pvar^)")
(assume "(beta1 ysumu)^" "OrLMRHyp")
(elim "OrLMRHyp")
;; 3,4
(assume "beta1^" "PHyp" "Hyp1" "Hyp2")
(use-with "Hyp1" (pt "beta1^") "PHyp")
;; 4
(assume "PHyp" "Hyp1" "Hyp2")
(use-with "Hyp2" "PHyp")
;; Proof finished.
(save "OrLMRElim")

;; OrRMRElim
(set-goal "all (uysum beta2)^(
 (OrRMR (cterm () Pvar1) (cterm (beta2^0) (Pvar beta2)^2 beta2^0))
 (uysum beta2)^ ->
 (Pvar1 -> Pvar^) -> all beta2^((Pvar beta2)^2 beta2^ -> Pvar^) -> Pvar^)")
(assume "(uysum beta2)^" "OrRMRHyp")
(elim "OrRMRHyp")
;; 3,4
(assume "PHyp" "Hyp1" "Hyp2")
(use-with "Hyp1" "PHyp")
;; 4
(assume "beta2^" "PHyp" "Hyp1" "Hyp2")
(use-with "Hyp2" (pt "beta2^") "PHyp")
;; Proof finished.
(save "OrRMRElim")

;; OrUMRElim
(set-goal "all boole((OrUMR (cterm () Pvar^1) (cterm () Pvar^2))boole ->
 (Pvar^1 -> Pvar^) -> (Pvar^2 -> Pvar^) -> Pvar^) ")
(ind)
;; 2,3
(assume "OrUMRHyp")
(elim "OrUMRHyp")
;; 5,6
(assume "P1" "Hyp1" "Hyp2")
(use-with "Hyp1" "P1")
;; 6
(assume "P2" "Hyp1" "Hyp2")
(use-with "Hyp2" "P2")
;; 3
(assume "OrUMRHyp")
(elim "OrUMRHyp")
;; 10,11
(assume "P1" "Hyp1" "Hyp2")
(use-with "Hyp1" "P1")
;; 11
(assume "P2" "Hyp1" "Hyp2")
(use-with "Hyp2" "P2")
;; Proof finished.
(save "OrUMRElim")

(set! COMMENT-FLAG #t)
