;;;; a bunch of handy macros for the ARM

;;;; This software is part of the SBCL system. See the README file for
;;;; more information.
;;;;
;;;; This software is derived from the CMU CL system, which was
;;;; written at Carnegie Mellon University and released into the
;;;; public domain. The software is in the public domain and is
;;;; provided with absolutely no warranty. See the COPYING and CREDITS
;;;; files for more information.

(in-package "SB!VM")

;;; Instruction-like macros.

(defmacro move (dst src)
  "Move SRC into DST unless they are location=."
  (once-only ((n-dst dst)
              (n-src src))
    `(unless (location= ,n-dst ,n-src)
       (inst mov ,n-dst ,n-src))))

(macrolet
    ((def (op inst shift)
       `(defmacro ,op (object base
                       &optional (offset 0) (lowtag 0) (predicate :al))
          `(inst ,',inst ,predicate ,object
                 (@ ,base (- (ash ,offset ,,shift) ,lowtag))))))
  (def loadw ldr word-shift)
  (def storew str word-shift))

(defmacro load-symbol-value (reg symbol)
  `(inst ldr ,reg (@ null-tn
                     (+ (static-symbol-offset ',symbol)
                        (ash symbol-value-slot word-shift)
                        (- other-pointer-lowtag)))))

(defmacro store-symbol-value (reg symbol)
  `(inst str ,reg (@ null-tn
                     (+ (static-symbol-offset ',symbol)
                        (ash symbol-value-slot word-shift)
                        (- other-pointer-lowtag)))))

;;; Macros to handle the fact that we cannot use the machine native call and
;;; return instructions.

(defmacro lisp-jump (function)
  "Jump to the lisp function FUNCTION."
  `(inst add pc-tn ,function
         (- (ash simple-fun-code-offset word-shift)
            fun-pointer-lowtag)))

(defmacro lisp-return (return-pc single-valued-p)
  "Return to RETURN-PC."
  `(progn
     ;; Indicate a single-valued return by clearing all of the status
     ;; flags, or a multiple-valued return by setting all of the status
     ;; flags.
     (inst msr (cpsr :f) ,(if single-valued-p 0 #xf0))
     #+(or) ;; Doesn't work, can't have a negative immediate value.
     (inst add pc-tn ,return-pc (- 4 other-pointer-lowtag))
     (inst sub pc-tn ,return-pc (- other-pointer-lowtag 4))))

(defmacro emit-return-pc (label)
  "Emit a return-pc header word.  LABEL is the label to use for this return-pc."
  `(progn
     (emit-alignment n-lowtag-bits)
     (emit-label ,label)
     (inst lra-header-word)))


;;;; Stack TN's

;;; Move a stack TN to a register and vice-versa.
(defmacro load-stack-tn (reg stack &optional (predicate :al))
  `(let ((reg ,reg)
         (stack ,stack))
     (let ((offset (tn-offset stack)))
       (sc-case stack
         ((control-stack)
          (loadw reg fp-tn offset 0 ,predicate))))))
(defmacro store-stack-tn (stack reg &optional (predicate :al))
  `(let ((stack ,stack)
         (reg ,reg))
     (let ((offset (tn-offset stack)))
       (sc-case stack
         ((control-stack)
          (storew reg fp-tn offset 0 ,predicate))))))

(defmacro maybe-load-stack-tn (reg reg-or-stack)
  "Move the TN Reg-Or-Stack into Reg if it isn't already there."
  (once-only ((n-reg reg)
              (n-stack reg-or-stack))
    `(sc-case ,n-reg
       ((any-reg descriptor-reg)
        (sc-case ,n-stack
          ((any-reg descriptor-reg)
           (move ,n-reg ,n-stack))
          ((control-stack)
           (loadw ,n-reg fp-tn (tn-offset ,n-stack))))))))

;;;; memory accessor vop generators

(defmacro define-full-reffer (name type offset lowtag scs el-type
                              &optional translate)
  `(define-vop (,name)
     ,@(when translate
             `((:translate ,translate)))
     (:policy :fast-safe)
     (:args (object :scs (descriptor-reg))
            (index :scs (any-reg)))
     (:arg-types ,type tagged-num)
     (:temporary (:scs (interior-reg)) lip)
     (:results (value :scs ,scs))
     (:result-types ,el-type)
     (:generator 5
       (inst add lip object index)
       (loadw value lip ,offset ,lowtag))))