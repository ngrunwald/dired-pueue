;;; dired-pueue.el --- Emacs dired integration for pueue -*- lexical-binding: t; -*-

;; Copyright (C) 2022 Nils Grunwald <github.com/ngrunwald>
;; Author: Nils Grunwald
;; URL: https://github.com/ngrunwald/dired-pueue
;; Created: 2022
;; Version: 0.1.0
;; Keywords: shell, async, queue, pueue, dired
;; Package-Requires: ((s "20220902.1511"))

;; This file is NOT part of GNU Emacs.

;; dired-pueue.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; dired-pueue.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with dired-pueue.el.
;; If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides Emacs functions to run various dired files actions through the pueue task queue.
;; It is intended to be used along the pueue package UI.

;;; Code:
(require 'seq)
(require 's)
(require 'subr-x)
(require 'dired)
(require 'dired-aux)
(require 'cl-lib)

(defgroup dired-pueue nil
  "dired-pueue customization group."
  :prefix "dired-pueue-"
  :group 'external)

(defcustom dired-pueue-program "pueue" "Name of the pueue program"
  :type 'string)
(defcustom dired-pueue-cp-program "cp" "Name of the copy program"
  :type 'string)
(defcustom dired-pueue-mv-program "mv" "Name of the move program"
  :type 'string)
(defcustom dired-pueue-group-name "dired-pueue" "Name of the pueue group for dired commands"
  :type 'string)

(defun dired-pueue--copy-cmd (sources target)
  (format "%s -v%s %s %s"
          dired-pueue-cp-program
          (if (not dired-recursive-copies) "" "r")
          (s-join " " (seq-map 'shell-quote-argument sources))
          (shell-quote-argument target)))

(defun dired-pueue--move-cmd (sources target)
  (format "%s %s %s"
          dired-pueue-mv-program
          (s-join " " (seq-map 'shell-quote-argument sources))
          (shell-quote-argument target)))

;;;###autoload
(defun dired-pueue-do-copy (&optional arg)
  "Replacement for `dired-do-copy' but made async through `pueue'."
  (interactive "P")
  (dired-pueue--do-op "Copy" 'copy 'dired-pueue--copy-cmd arg))

;;;###autoload
(defun dired-pueue-do-rename (&optional arg)
  "Replacement for `dired-do-rename' but made async through `pueue'."
  (interactive "P")
  (dired-pueue--do-op "Rename" 'move 'dired-pueue--move-cmd arg))

(defun dired-pueue--do-op (op-name op-symbol op-fn &optional arg)
  (let* ((fn-list (dired-get-marked-files nil arg nil nil t))
         (rfn-list (mapcar #'dired-make-relative fn-list))
         (dired-one-file	;; fluid variable inside dired-create-files
          (and (consp fn-list) (null (cdr fn-list)) (car fn-list)))
         (target-dir (dired-dwim-target-directory))
         (default (and dired-one-file
                       (not dired-dwim-target) ;; Bug#25609
                       (expand-file-name (file-name-nondirectory (car fn-list))
                                         target-dir)))
         (defaults (dired-dwim-target-defaults fn-list target-dir))
         (target (expand-file-name ;; fluid variable inside dired-create-files
                  (minibuffer-with-setup-hook
                      (lambda ()
                        (set (make-local-variable 'minibuffer-default-add-function) nil)
                        (setq minibuffer-default defaults))
                    (dired-mark-read-file-name
                     (format "%s %%s: "
                             op-name)
                     target-dir op-symbol arg rfn-list default))))
         (cmd (funcall op-fn rfn-list target))
         (pueue-cmd (format "%s add --group=%s --label=%s --print-task-id -- %s"
                            dired-pueue-program
                            dired-pueue-group-name
                            op-name
                            cmd))
         (id (shell-command-to-string pueue-cmd)))
    (message "Added %s in pueue: ID %s" op-name id)
    id))

;;;###autoload
(defun dired-pueue-do-shell-command (command &optional arg file-list)
  "Replacement for `dired-do-shell-command' but made async through `pueue'."
  (interactive
   (let ((files (dired-get-marked-files t current-prefix-arg nil nil t)))
     (list
      ;; Want to give feedback whether this file or marked files are used:
      (dired-read-shell-command "! on %s: " current-prefix-arg files)
      current-prefix-arg
      files)))
  (cl-letf (((symbol-function 'dired-run-shell-command)
             (lambda (cmd)
               (let ((cmds (s-split ";" cmd t)))
                 (seq-each (lambda (c) (shell-command-to-string
                                        (format "%s add --group=%s --print-task-id --escape -- %s"
                                                dired-pueue-program
                                                dired-pueue-group-name
                                                c)))
                           cmds)
                 (message "Added %d jobs to pueue" (length cmds)))
               ;; Return nil for sake of nconc in dired-bunch-files.
               nil)))
    (dired-do-shell-command (s-replace-regexp " ?;?&;?$" "" command) arg file-list)))

(defun dired-pueue-setup-group ()
  "Initial setup for dired-pueue group."
  (interactive)
  (start-process "dired-pueue-setup-group" nil dired-pueue-program "group" "add" dired-pueue-group-name))

(with-eval-after-load "dired-pueue"
  (dired-pueue-setup-group))

(provide 'dired-pueue)
;;; dired-pueue.el ends here
