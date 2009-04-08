;;; Compiled by f2cl version:
;;; ("f2cl1.l,v 1.215 2009/04/07 22:05:21 rtoy Exp $"
;;;  "f2cl2.l,v 1.37 2008/02/22 22:19:33 rtoy Exp $"
;;;  "f2cl3.l,v 1.6 2008/02/22 22:19:33 rtoy Exp $"
;;;  "f2cl4.l,v 1.7 2008/02/22 22:19:34 rtoy Exp $"
;;;  "f2cl5.l,v 1.200 2009/01/19 02:38:17 rtoy Exp $"
;;;  "f2cl6.l,v 1.48 2008/08/24 00:56:27 rtoy Exp $"
;;;  "macros.l,v 1.112 2009/01/08 12:57:19 rtoy Exp $")

;;; Using Lisp CMU Common Lisp 19f (19F)
;;; 
;;; Options: ((:prune-labels nil) (:auto-save t) (:relaxed-array-decls t)
;;;           (:coerce-assigns :as-needed) (:array-type ':array)
;;;           (:array-slicing t) (:declare-common nil)
;;;           (:float-format double-float))

(in-package :blas)


(let* ((one 1.0) (zero 0.0))
  (declare (type (double-float 1.0 1.0) one)
           (type (double-float 0.0 0.0) zero)
           (ignorable one zero))
  (defun dznrm2 (n x incx)
    (declare (type (array f2cl-lib:complex16 (*)) x)
             (type (f2cl-lib:integer4) incx n))
    (f2cl-lib:with-multi-array-data
        ((x f2cl-lib:complex16 x-%data% x-%offset%))
      (prog ((norm 0.0) (scale 0.0) (ssq 0.0) (temp 0.0) (ix 0) (dznrm2 0.0))
        (declare (type (f2cl-lib:integer4) ix)
                 (type (double-float) norm scale ssq temp dznrm2))
        (cond
          ((or (< n 1) (< incx 1))
           (setf norm zero))
          (t
           (setf scale zero)
           (setf ssq one)
           (f2cl-lib:fdo (ix 1 (f2cl-lib:int-add ix incx))
                         ((> ix
                             (f2cl-lib:int-add 1
                                               (f2cl-lib:int-mul
                                                (f2cl-lib:int-add n
                                                                  (f2cl-lib:int-sub
                                                                   1))
                                                incx)))
                          nil)
             (tagbody
               (cond
                 ((/= (f2cl-lib:dble (f2cl-lib:fref x (ix) ((1 *)))) zero)
                  (setf temp
                          (abs
                           (f2cl-lib:dble
                            (f2cl-lib:fref x-%data% (ix) ((1 *)) x-%offset%))))
                  (cond
                    ((< scale temp)
                     (setf ssq (+ one (* ssq (expt (/ scale temp) 2))))
                     (setf scale temp))
                    (t
                     (setf ssq (+ ssq (expt (/ temp scale) 2)))))))
               (cond
                 ((/= (f2cl-lib:dimag (f2cl-lib:fref x (ix) ((1 *)))) zero)
                  (setf temp
                          (abs
                           (f2cl-lib:dimag
                            (f2cl-lib:fref x-%data% (ix) ((1 *)) x-%offset%))))
                  (cond
                    ((< scale temp)
                     (setf ssq (+ one (* ssq (expt (/ scale temp) 2))))
                     (setf scale temp))
                    (t
                     (setf ssq (+ ssq (expt (/ temp scale) 2)))))))
              label10))
           (setf norm (* scale (f2cl-lib:fsqrt ssq)))))
        (setf dznrm2 norm)
        (go end_label)
       end_label
        (return (values dznrm2 nil nil nil))))))

(in-package #-gcl #:cl-user #+gcl "CL-USER")
#+#.(cl:if (cl:find-package '#:f2cl) '(and) '(or))
(eval-when (:load-toplevel :compile-toplevel :execute)
  (setf (gethash 'fortran-to-lisp::dznrm2
                 fortran-to-lisp::*f2cl-function-info*)
          (fortran-to-lisp::make-f2cl-finfo
           :arg-types '((fortran-to-lisp::integer4)
                        (array fortran-to-lisp::complex16 (*))
                        (fortran-to-lisp::integer4))
           :return-values '(nil nil nil)
           :calls 'nil)))

