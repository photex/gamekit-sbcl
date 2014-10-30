;;; Now that we use the compiler for macros, interpreted /SHOW doesn't
;;; work until later in init.
#+sb-show (print "/hello, world!")

;;; Do warm init without compiling files.
(defvar *compile-files-p* nil)
#+sb-show (print "/about to LOAD warm.lisp (with *compile-files-p* = NIL)")
(let ((*print-length* 10)
      (*print-level* 5)
      (*print-circle* t))
  (load "src/cold/warm.lisp"))

;;; Unintern no-longer-needed stuff before the possible PURIFY in
;;; SAVE-LISP-AND-DIE.
#-sb-fluid (sb-impl::!unintern-init-only-stuff)

(sb-int:/show "done with warm.lisp, about to GC :FULL T")
(sb-ext:gc :full t)

;;; resetting compilation policy to neutral values in preparation for
;;; SAVE-LISP-AND-DIE as final SBCL core (not in warm.lisp because
;;; SB-C::*POLICY* has file scope)
(sb-int:/show "setting compilation policy to neutral values")
(proclaim
 '(optimize
   (compilation-speed 1) (debug 1) (inhibit-warnings 1)
   (safety 1) (space 1) (speed 1)))

;;; Lock internal packages
#+sb-package-locks
(dolist (p (list-all-packages))
  (unless (member p (mapcar #'find-package '("KEYWORD" "CL-USER")))
    (sb-ext:lock-package p)))

(sb-int:/show "done with warm.lisp, about to SAVE-LISP-AND-DIE")
;;; Even if /SHOW output was wanted during build, it's probably
;;; not wanted by default after build is complete. (And if it's
;;; wanted, it can easily be turned back on.)
#+sb-show (setf sb-int:*/show* nil)
;;; The system is complete now, all standard functions are
;;; defined.
;;; The call to CTYPE-OF-CACHE-CLEAR is probably redundant.
;;; SAVE-LISP-AND-DIE calls DEINIT which calls DROP-ALL-HASH-CACHES.
(sb-kernel::ctype-of-cache-clear)
(setq sb-c::*flame-on-necessarily-undefined-thing* t)

;;; Clean up stray symbols from the CL-USER package.
(with-package-iterator (iter "CL-USER" :internal :external)
  (loop (multiple-value-bind (winp symbol) (iter)
          (if winp (unintern symbol "CL-USER") (return)))))

(sb-ext:save-lisp-and-die "output/sbcl.core")
