;;; -*-  Mode: Lisp; Package: Maxima; Syntax: Common-Lisp; Base: 10 -*- ;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;     The data in this file contains enhancments.                    ;;;;;
;;;                                                                    ;;;;;
;;;  Copyright (c) 1984,1987 by William Schelter,University of Texas   ;;;;;
;;;     All rights reserved                                            ;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;       (c) Copyright 1982 Massachusetts Institute of Technology       ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(in-package :maxima)
(macsyma-module mload)

;; I decided to move most of the file hacking utilities I used in TRANSL to
;; this file. -GJC

;; Concepts:
;; Lisp_level_filename. Anything taken by the built-in lisp I/O primitives.
;;
;; User_level_filename. Comes through the macsyma reader, so it has an extra "&"
;;   in the pname in the case of "filename" or has extra "$" and has undergone
;;   ALIAS transformation in the case of 'FOOBAR or '[FOO,BAR,BAZ].
;;
;; Canonical_filename. Can be passed to built-in lisp I/O primitives, and
;;   can also be passed back to the user, is specially handled by the DISPLAY.
;;
;; Functions:
;; $FILENAME_MERGE. Takes User_level_filename(s) and Canonical_filename(s) and
;;   merges them together, returning a Canonical_filename.
;;
;; TO-MACSYMA-NAMESTRING. Converts a Lisp_level_filename to a Canonical_filename
;;
;; $FILE_SEARCH ............ Takes a user or canonical filename and a list of types of
;;                           applicable files to look for.
;; $FILE_TYPE   ............. Takes a user or canonical filename and returns
;;                            NIL, $MACSYMA, $LISP, or $FASL.
;; CALL-BATCH1 ............. takes a canonical filename and a no-echop flag.

;;------
;;There is also this problem of what file searching and defaulting means,
;; especially when this is done across systems.  My feeling right now
;; is that searching might actually be three-layered:
;; host, device/directory, type [assuming a name is given].  This will become
;; important in the near future because NIL is going to be supporting
;; multiple hosts over DECNET, using the common-lisp/lispm model of pathnames
;; and hosts.  One of the problems with incremental merging algorithms like
;; are used here is that making a pathname the first time tends to force an
;; interpretation with respect to some specific host, which is probably
;; defaulted from some place used for ultimate defaulting and not normally
;; used by higher-level facilities like LOAD.  --gsb
;;------

(declare-top (special $file_search_lisp $file_search_maxima $file_search_demo $loadprint))

(defmfun $listp_check (var val)
  "Gives an MAXIMA-ERROR message including its first argument if its second
  argument is not a LIST"
  (or ($listp val)
      (merror "The variable ~:M being set to a non-`listp' object:~%~M"
	      var val)))

(defprop $file_search $listp_check assign)

(defprop $file_types $listp_check assign)

(defun $load_search_dir ()
  (to-macsyma-namestring *default-pathname-defaults*))


(defmfun load-and-tell (filename)
  (loadfile filename t ;; means this is a lisp-level call, not user-level.
	    $loadprint))

(defun to-macsyma-namestring (x)
  (pathname x))
       
(defun macsyma-namestringp (x)
  (typep x 'pathname))
       
(defun errset-namestring (x)
  (let ((errset nil))
    (errset (pathname x) nil)))

(defmfun $filename_merge (&rest file-specs)
  (setq file-specs
	(if file-specs 
	    (mapcar #'macsyma-namestring-sub file-specs)
	    '("**")))
  (progn
    (to-macsyma-namestring (if (null (cdr file-specs))
			       (car file-specs)
			       (apply #'mergef file-specs)))))


(defun macsyma-namestring-sub (user-object)
  (if (macsyma-namestringp user-object) user-object
      (let* ((system-object
	      (cond ((and (atom user-object) (not (symbolp user-object)))
		     user-object)
		    ;; The following clause takes care of |&Foo|,
		    ;; which comes from the Maxima string "Foo".
		    ((atom user-object)	;hence a symbol in view of the
		     (print-invert-case (fullstrip1 user-object))) ; first clause
		    (($listp user-object)
		     (fullstrip (cdr user-object)))
		    (t
		     (merror "Bad file spec:~%~M" user-object))))
	     (namestring-try (errset-namestring system-object)))
	(if namestring-try (car namestring-try)
	    ;; know its small now, so print on same line.
	    (merror "Bad file spec: ~:M" user-object)))))

(defmfun open-out-dsk (x)
  (open x :direction :output :element-type 'character))

(defmfun open-in-dsk (x)
  (open x :direction :input :element-type 'character))

(defun $batchload (filename &aux expr (*mread-prompt* ""))
  (declare (special *mread-prompt*))
  (setq filename ($file_search1 filename '((mlist) $file_search_maxima)))
  (with-open-file (in-stream filename)
    (when $loadprint
      (format t "~&batching ~A~&" (cl:namestring (truename in-stream))))
    (cleanup)
    (newline in-stream)
    (loop while (and
		  (setq  expr (mread in-stream nil))
		  (consp expr))
	   do (meval* (third expr)))
		  (cl:namestring (truename in-stream))))

;;returns appropriate error or existing pathname.
;; the second argument is a maxima list of variables
;; each of which contains a list of paths.   This is
;; so users can correct the variable..
(defun $file_search1 (name search-lists &aux lis)
  (if (pathnamep name)
      (setq name (namestring name)))
  (setq lis (apply '$append (mapcar 'symbol-value (cdr search-lists))))
  (let ((res ($file_search name lis)))
    (or res
	(merror "Could not find `~M' using paths in ~A."
		name
		(string-trim "[]" ($sconcat search-lists))))))

(defmfun $load (filename)
  "This is the generic file loading function.
  LOAD(filename) will either BATCHLOAD or LOADFILE the file,
  depending on wether the file contains Macsyma, Lisp, or Compiled
  code. The file specifications default such that a compiled file
  is searched for first, then a lisp file, and finally a macsyma batch
  file. This command is designed to provide maximum utility and
  convenience for writers of packages and users of the macsyma->lisp
  translator."

  (cond ((and (symbolp filename) (not (mstringp filename)))
	 (setq filename (string-downcase (symbol-name (stripdollar filename))))))
  (let ((searched-for
	 ($file_search1 filename
			'((mlist) $file_search_maxima $file_search_lisp  )))
	type)
    (setq type ($file_type searched-for))
    (case type
      (($maxima)
       ($batchload searched-for))
      (($lisp $object)
       ;; do something about handling errors
       ;; during loading. Foobar fail act errors.
       (load-and-tell searched-for))
      (t
       (merror "Maxima bug: Unknown file type ~M" type)))
    searched-for))


(defun $file_type (fil &aux typ)
  (setq fil (pathname fil))
  (setq typ (format nil "~(~A~)" (pathname-type fil)))
  (or 
   (and (> (length typ) 0)
	(let ((ch (aref typ 0)))
	  (cdr (assoc ch '((#\m . $maxima)
			   (#\d . $maxima)
			   (#\l . $lisp)
			   (#\o . $object)
			   (#\f . $object))))))
   '$object))
       			

(defvar *macsyma-startup-queue* nil)

(declaim (special *mread-prompt*))

;;;; batch & demo search hacks

(defun $batch (filename &optional (demo :batch)
	       &aux tem   (possible '(:demo :batch :test)))
  "giving a second argument makes it use demo mode, ie pause after evaluation
   of each command line"
  (cond ((setq tem (member ($mkey demo) possible :test #'eq))
	 (setq demo (car tem)))
	(t (format t "Second arg ~A is not in ~A so using :Batch"
		   demo possible)))

  (setq filename ($file_search1 filename
				(if (eql demo :demo)
				    '((mlist) $file_search_demo )
				    '((mlist) $file_search_maxima ))))
  (cond ((eq demo :test)
	 (test-batch filename nil :show-all t))
	(t
	 (with-open-file (in-stream filename)
	   (format t "~%batching ~A~%"
		   (truename in-stream))
	   (continue in-stream demo)
	   (namestring in-stream)))))

;; Return true if $float converts both a and b to floats and 
;; |a - b| <= 8 * double-float-epsilon * min(|a|, |b|). In all
;; other cases, return false.

(defun $dfloat_approx_equal (a b)
  (setq a (if (floatp a) a ($float a)))
  (setq b (if (floatp b) b ($float b)))
  (and
   (floatp a)
   (floatp b)
   (<= (abs (- a b)) (* 8 double-float-epsilon (min (abs a) (abs b))))))

;; Return true if $bfloat converts both a and b to big floats and 
;; |a - b| <= 8 * big-float-epsilon * min(|a|, |b|). The big float
;; epsilon is determined by the number with the greatest number of bits.

(defun $bfloat_approx_equal (a b)
  (setq a (if ($bfloatp a) a ($bfloat a)))
  (setq b (if ($bfloatp b) b ($bfloat b)))
  (and
   ($bfloatp a)
   ($bfloatp b)
   (eq t (mgqp (mul (power 2 (- 8 (max (first (last (first a))) (first (last (first b))))))
		    (take '($min) (take '(mabs) a) (take '(mabs) b)))
	       (take '(mabs) (sub a b))))))

;; The first argument 'f' is the expected result; the second argument 
;; 'g' is the output of the test. By explicit evaluation, the expected 
;; result *can* be a CL array, CL hashtable, or a taylor polynomial. Such
;; a test would look something like (yes, it's a silly test)

;;    taylor(x,x,0,2);
;;    ''(taylor(x,x,0,2)
 
(defun approx-alike (f g)
 
  (cond ((floatp f) (and (floatp g) ($dfloat_approx_equal f g)))
	
	(($bfloatp f) (and ($bfloatp g) ($bfloat_approx_equal f g)))
	
	(($taylorp g)
	 (approx-alike 0 (sub (ratdisrep f) (ratdisrep g))))
	
	((atom f) (and (atom g) (equal f g)))
		     
	((op-equalp f 'lambda)
	 (and (op-equalp g 'lambda)
	      (approx-alike-list (mapcar #'(lambda (s) (simplifya s nil)) (margs f))
				 (mapcar #'(lambda (s) (simplifya s nil)) (margs g)))))
	
	((arrayp f)
	 (and (arrayp g) (approx-alike ($listarray f) ($listarray g))))
	
	((hash-table-p f)
	 (and (hash-table-p g) (approx-alike ($listarray f) ($listarray g))))
	
	(($ratp f)
	 (and ($ratp g) (approx-alike (ratdisrep f) (ratdisrep g))))
	
	;; maybe we don't want this.
	((op-equalp f 'mquote)
	 (approx-alike (second f) g))
	 
	;; I'm pretty sure that (mop f) and (mop g) won't signal errors, but
	;; let's be extra careful.

	((and (consp f) (consp (car f)) (consp g) (consp (car g))
	      (or (approx-alike (mop f) (mop g)) 
		  (and (symbolp (mop f)) (symbolp (mop g))
		       (approx-alike ($nounify (mop f)) ($nounify (mop g)))))
	      (approx-alike-list (margs f) (margs g))))
	
	(t nil)))

(defun approx-alike-list (p q)
  (cond ((null p) (null q))
	((null q) (null p))
	(t (and (approx-alike (first p) (first q)) (approx-alike-list (rest p) (rest q))))))

(defun simple-equal-p (f g)
  (approx-alike (simplifya f nil) (simplifya g nil)))

(defun batch-equal-check (expected result)
  (let ((answer (catch 'macsyma-quit (simple-equal-p expected result))))
    (if (eql answer 'maxima-error) nil answer)))

(defvar *collect-errors* t)

(defun in-list (item list)
  (dolist (element list)
    (if (equal item element) (return-from in-list t))) nil)


(defun test-batch (filename expected-errors
			    &key (out *standard-output*) (show-expected nil)
			    (show-all nil))

  (let ((result) (next-result) (next) (error-log) (all-differences nil) ($ratprint nil) (strm)
	(*mread-prompt* "") (expr) (num-problems 0) (tmp-output) (save-output) (i 0))
    
    (cond (*collect-errors*
	   (setq error-log
		 (if (streamp *collect-errors*) *collect-errors*
		   (handler-case
		       (open (alter-pathname filename :type "ERR") :direction :output :if-exists :supersede)
		     #-gcl (file-error () nil)
		     #+gcl (cl::error () nil))))
	   (when error-log
	     (format t "~%Error log on ~a" error-log)
	     (format error-log "~%/*    maxima-error log for testing of ~A" filename)
	     (format error-log "*/~2%"))))
 
    (unwind-protect 
	(progn
	  (setq strm (open filename :direction :input))
	  (while (not (eq 'eof (setq expr (mread strm 'eof))))
	    (incf num-problems)
	    (incf i)
	    (setf tmp-output (make-string-output-stream))
	    (setf save-output *standard-output*)
	    (setf *standard-output* tmp-output)
	  
	    (unwind-protect
		(progn
		  (setq result (meval* `(($errcatch) ,(third expr))))
		  (setq result (if ($emptyp result) 'error-catch (second result)))
		  (setq $% result))
	      (setf *standard-output* save-output))

	    (setq next (mread strm 'eof))
	    (if (eq next 'eof) (merror "Missing expected result"))
	  
	    (setq next-result (third next))
	    (let* ((correct (batch-equal-check next-result result))
		   (expected-error (in-list i expected-errors))
		   (pass (or correct expected-error)))
	      (if (or show-all (not pass) (and correct expected-error)
		      (and expected-error show-expected))
		  (progn
		    (format out "~%********************** Problem ~A ***************" i)
		    (format out "~%Input:~%" )
		    (displa (third expr))
		    (format out "~%~%Result:~%")
		    (format out "~a" (get-output-stream-string tmp-output))
		    (displa $%)))
	      (cond ((and correct expected-error)
		     (format t "~%... Which was correct, but was expected to be wrong due to a known bug in~% Maxima.~%"))
		    (correct
		     (if show-all (format t "~%... Which was correct.~%")))
		    ((and (not correct) expected-error)
		     (if (or show-all show-expected)
			 (progn
			   (format t "~%This is a known error in Maxima. The correct result is:~%")
			   (displa next-result))))
		    (t (format t "~%This differed from the expected result:~%")
		       (push i all-differences)
		       (displa next-result)
		       (cond ((and *collect-errors* error-log)
			      (mgrind (third expr) error-log)
			      (list-variable-bindings (third expr) error-log)
			      (format error-log ";~%")
			      (format error-log "//*Erroneous Result?:~%")
			      (mgrind result error-log) (format error-log "*// ")
			      (terpri error-log)
			      (mgrind next-result error-log)
			      (format error-log ";~%~%"))))))))
      (close strm))
    (cond (error-log
	   (or (streamp *collect-errors*)
	       (close error-log))))
    (cond ((null all-differences)
	   (format t "~a/~a tests passed.~%" num-problems num-problems) '((mlist)))
	  (t (progn
	       (format t "~%~a/~a tests passed.~%" 
		       (- num-problems (length all-differences)) num-problems)
	       (let ((s (if (> (length all-differences) 1) "s" "")))
		 (format t "~%The following ~A problem~A failed: ~A~%" 
			 (length all-differences) s (reverse all-differences)))
	       `((mlist),filename ,@ all-differences))))))
	   
;;to keep track of global values during the error:
(defun list-variable-bindings (expr &optional str &aux tem)
  (loop for v in(cdr ($listofvars  expr))
    when (member v $values :test #'equal)
    collecting (setq tem`((mequal) ,v ,(meval* v)))
    and
    do (cond (str (format str ",")(mgrind tem str)))))

;;in init_max
;; name = foo or foo.type or dir/foo.type or dir/foo 
;; the empty parts are filled successively from defaults in templates in
;; the path.   A template may use multiple {a,b,c} constructions to indicate
;; multiple possiblities.  eg foo.l{i,}sp or foo.{dem,dm1,dm2}
(defun $file_search (name &optional paths)
  (if (and (symbolp name)
	   (member (char (symbol-name name) 0) '(#\& #\$)))
      (setq name (subseq (print-invert-case name) 1)))
  (if (symbolp name)  (setf name (string name)))
  (if (probe-file name) (return-from $file_search name))
  (or paths (setq paths ($append $file_search_lisp  $file_search_maxima
				 $file_search_demo)))
  (atomchk paths '$file_search t)
  (new-file-search (string name) (cdr paths)))

(defun new-file-search (name template)
  (cond ((probe-file name))
	((atom template)
     (if (mstringp template)
       (setq template (subseq (maybe-invert-string-case (string template)) 1)))
	 (let ((lis (loop for w in (split-string template "{}")
			  when (null (position #\, w))
			  collect w
			  else
			  collect (split-string w ","))))
	   (new-file-search1 name "" lis)))
	(t
	 (let ((temp nil))
	   (loop for v in template
		 when (setq temp (new-file-search name v))
		 do (return temp))))))

(defun new-file-search1 (name begin lis)
  (cond ((null lis)
	 (let ((file (namestring ($filename_merge begin name))))
	   (if (probe-file file) file nil)))
	((atom (car lis))
	 (new-file-search1 name
			   (if begin
			       ($sconcat begin (car lis)) (car lis))
			   (cdr lis)))
	(t (loop for v in (car lis) with tem
		  when (setq tem  (new-file-search1 name begin (cons v (cdr lis))))
		  do (return tem)))))

(defun save-linenumbers (&key (c-lines t) d-lines (from 1) (below $linenum) a-list
			 (file  "/tmp/lines")
			 &aux input-symbol (linel 79))
  (cond ((null a-list) (setq a-list (loop for i from from below below collecting i))))
  (with-open-file (st file :direction :output)
    (format st "/* -*- Mode: MACSYMA; Package: MACSYMA -*- */")
    (format st "~%~%       /*    ~A     */  ~%"
	    (let ((tem (cdddr
				(multiple-value-list (get-decoded-time)))))
		      (format nil "~a:~a:~a" (car tem) (cadr tem) (caadr tem))))
    (loop for i in a-list
	   when (and c-lines (boundp (setq input-symbol (intern (format nil "$~A~A" '#:c i)))))
	   do
	   (format st "~% C~3A;  "   i)
	   (mgrind (symbol-value input-symbol) st)
	   (format st ";")
	   when (and d-lines
		     (boundp (setq input-symbol (intern (format nil "$~A~A" '#:d i)))))
	   do
	   (format st "~% D~3A:  "   i)
	   (mgrind (symbol-value input-symbol) st)
	   (format st "$"))))


(defun $printfile (file)
  (setq file ($file_search1 file '((mlist) $file_search_usage)))
  (with-open-file (st file)
    (loop
       with tem
       while (setq tem (read-char st nil 'eof)) 
       do
       (if (eq tem 'eof) (return t))
       (princ tem))
    (namestring file)))

  
  
(defmvar $testsuite_files nil)

(defvar *maxima-testsdir*)

(defun intersect-tests (tests)
  ;; If TESTS is non-NIL, we assume it's a Maxima list of (maxima)
  ;; strings naming the tests we want to run.  They must match the
  ;; file names in $testsuite_files.  We ignore any items that aren't
  ;; in $testsuite_files.
  (mapcar #'(lambda (x)
	      (if (symbolp x)
		  (subseq (print-invert-case x) 1)
		  x))
	  (cond (tests
		 (intersection (cdr $testsuite_files)
			       (cdr tests)
			       :key #'(lambda (x)
					(maxima-string (if (listp x)
							   (second x)
							   x)))
			       :test #'string=))
		(t
		 (cdr $testsuite_files)))))

(defun $run_testsuite (&optional (show-known-bugs nil) (show-all nil) (tests nil))
  (declare (special $file_search_tests))
  (let ((test-file)
	(expected-failures))
    (setq *collect-errors* nil)
    (unless $testsuite_files
      (load (concatenate 'string *maxima-testsdir* "/" "testsuite.lisp")))
    (let ((error-break-file)
	  (testresult)
	  (tests-to-run (intersect-tests tests)))
      (time 
       (loop with errs = '() for testentry in tests-to-run
	      do
	      (if (atom testentry)
		  (progn
		    (setf test-file testentry)
		    (setf expected-failures nil))
		  (progn
		    (setf test-file (second testentry))
		    (setf expected-failures (cddr testentry))))
  
	    (format t "Running tests in ~a: " (if (symbolp test-file)
						    (subseq (print-invert-case test-file) 1)
						    test-file))
	      (or (errset
		   (progn
		     (setq testresult 
			   (rest (test-batch
				  ($file_search test-file $file_search_tests)
				  expected-failures
				  :show-expected show-known-bugs
				  :show-all show-all)))
		     (if testresult
			 (setq errs (append errs (list testresult))))))
		  (progn
		    (setq error-break-file (format nil "~a" test-file))
		    (setq errs 
			  (append errs 
				  (list (list error-break-file "error break"))))
		    (format t "~%Caused an error break: ~a~%" test-file)))
	      finally (cond ((null errs) 
			     (format t "~%~%No unexpected errors found.~%"))
			    (t (format t "~%Error summary:~%")
			       (mapcar
				#'(lambda (x)
				    (let ((s (if (> (length (rest x)) 1) "s" "")))
				      (format t "Error~a found in ~a, problem~a:~%~a~%"
				       s (first x) s (sort (rest x) #'<))))
				errs)))))))
  '$done)


