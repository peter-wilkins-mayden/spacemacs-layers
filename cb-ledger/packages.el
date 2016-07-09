;;; packages.el --- cb-ledger Layer packages File for Spacemacs
;;; Commentary:
;;; Code:

(defconst cb-ledger-packages
  '(ledger-mode
    (cb-ledger-reports :location local)
    (cb-ledger-format :location local))
  "List of all packages to install and/or initialize. Built-in packages
which require an initialization must be listed explicitly in the list.")

(defun cb-ledger/user-config ()
  ;; Set this keybinding late so that Spacemacs does not clobber it.
  (spacemacs/set-leader-keys "o$" #'cb-ledger-goto-ledger-file))

(eval-when-compile
  (require 'dash nil t)
  (require 'use-package nil t))

(defun cb-ledger/post-init-ledger-mode ()
  (use-package ledger-mode
    :mode ("\.ledger$" . ledger-mode)
    :config
    (progn
      (setq ledger-master-file (f-join org-directory "accounts.ledger"))
      (setq ledger-post-account-alignment-column 2)
      (setq ledger-post-use-completion-engine :ido)
      (setq ledger-fontify-xact-state-overrides nil)

      ;; Faces and font-locking

      (defface ledger-date
        `((t :inherit org-date :underline nil :foreground ,solarized-hl-cyan))
        "Face for dates at start of transactions."
        :group 'ledger-faces)

      (defface ledger-periodic-header
        `((t :foreground ,solarized-hl-violet :bold t))
        "Face for the header for periodic transactions."
        :group 'ledger-faces)

      (defface ledger-year-line
        `((t :foreground ,solarized-hl-violet))
        "Face for year declarations."
        :group 'ledger-faces)

      (defface ledger-report-negative-amount
        `((t (:foreground ,solarized-hl-red)))
        "Face for negative amounts in ledger reports."
        :group 'ledger-faces)

      (font-lock-add-keywords
       'ledger-mode
       `((,(rx bol (+ (any digit "=" "/"))) . 'ledger-date)
         (,(rx bol "~" (* nonl)) . 'ledger-periodic-header)
         (,(rx bol "year" (+ space) (+ digit) (* space) eol) . 'ledger-year-line)))

      (font-lock-add-keywords
       'ledger-report-mode
       `((,(rx "$" (* space) "-" (+ digit) (? "." (+ digit))) . 'ledger-report-negative-amount)
         (,(rx (+ digit) "-" (= 3 alpha) "-" (+ digit)) . 'ledger-date)))

      (custom-set-faces
       '(ledger-occur-xact-face
         ((((background dark))  :background "#073642")
          (((background light)) :background "#eee8d5")))
       `(ledger-font-pending-face
         ((t (:foreground ,solarized-hl-orange))))
       `(ledger-font-payee-cleared-face
         ((t (:foreground ,solarized-hl-green))))
       `(ledger-font-payee-uncleared-face
         ((t (:foreground ,solarized-hl-orange))))
       `(ledger-font-posting-account-face
         ((t (:foreground ,solarized-hl-blue)))))

      (core/remap-face 'ledger-font-comment-face 'font-lock-comment-face)

      ;; Fix font lock issue in ledger reports
      (add-hook 'ledger-report-mode-hook 'font-lock-fontify-buffer)

      ;;; Keybindings

      (define-key ledger-mode-map (kbd "C-c C-c") #'ledger-report)
      (define-key ledger-mode-map (kbd "M-RET")   #'ledger-toggle-current-transaction)
      (define-key ledger-mode-map (kbd "C-c C-.") #'cb-ledger-insert-timestamp)


      (defun cb-ledger/report-from-report-buffer ()
        (interactive)
        (let ((buf (--first (with-current-buffer it
                              (derived-mode-p 'ledger-mode))
                            (buffer-list))))
          (pop-to-buffer buf)
          (call-interactively #'ledger-report)))

      (define-key ledger-report-mode-map (kbd "C-c C-c") #'cb-ledger/report-from-report-buffer)
      (evil-define-key 'normal ledger-report-mode-map (kbd "q") #'kill-buffer-and-window)

      ;; Hide command name from reports.

      (with-eval-after-load 'ledger-report
        (defun ledger-do-report (cmd)
          (goto-char (point-min))
          (insert (format "Report: %s\n" ledger-report-name)
                  (make-string (- (window-width) 1) ?=)
                  "\n\n")
          (let ((data-pos (point))
                (register-report (string-match " reg\\(ister\\)? " cmd))
                files-in-report)
            (shell-command
             ;; --subtotal does not produce identifiable transactions, so don't
             ;; prepend location information for them
             cmd
             t nil)
            (when register-report
              (goto-char data-pos)
              (while (re-search-forward "^\\(/[^:]+\\)?:\\([0-9]+\\)?:" nil t)
                (let ((file (match-string 1))
                      (line (string-to-number (match-string 2))))
                  (delete-region (match-beginning 0) (match-end 0))
                  (when file
                    (set-text-properties (line-beginning-position) (line-end-position)
                                         (list 'ledger-source (cons file (save-window-excursion
                                                                           (save-excursion
                                                                             (find-file file)
                                                                             (widen)
                                                                             (ledger-navigate-to-line line)
                                                                             (point-marker))))))
                    (add-text-properties (line-beginning-position) (line-end-position)
                                         (list 'font-lock-face 'ledger-font-report-clickable-face))
                    (end-of-line)))))
            (goto-char data-pos)))))))

(defun cb-ledger/init-cb-ledger-reports ()
  (use-package cb-ledger-reports
    :after ledger-mode
    :config
    (cl-flet* ((header-args (title)
                            (format "\n\n%s\n%s\n" title (s-repeat (length title) "=")))
               (header-1 (title) (concat "echo " (shell-quote-argument (s-trim-left (header-args title)))))
               (header (title) (concat "echo " (shell-quote-argument (header-args title))))

               (paragraph (s)
                          (let ((filled
                                 (with-temp-buffer
                                   (org-mode)
                                   (insert s)
                                   (org-fill-paragraph)
                                   (while (zerop (forward-line))
                                     (org-fill-paragraph))
                                   (goto-char (point-max))
                                   (newline)
                                   (newline)
                                   (buffer-string))))
                            (format "echo %s" (shell-quote-argument filled))))

               (separator () (format "echo %s" (shell-quote-argument (concat "\n\n" (s-repeat 80 "=") "\n"))))
               (report-from-list (ls) (s-join " && " ls)))

      (setq cb-ledger-reports-income-payee-name "Income:Movio")

      (setq ledger-report-format-specifiers
            '(("ledger-file" . ledger-report-ledger-file-format-specifier)
              ("last-payday" . cb-ledger-reports-last-payday)
              ("prev-pay-period" . cb-ledger-reports-previous-pay-period)
              ("account" . ledger-report-account-format-specifier)))

      (let ((weekly-review
             (list
              (paragraph "Skim over balances to make sure they look right.")

              (header-1 "Assets")
              "ledger -f %(ledger-file) bal Assets --depth 2"

              (header "Overall Spending Last 7 Days")
              "ledger -f %(ledger-file) bal 'checking' 'bills' -p 'last 7 days'"

              (header "Expenses Last 7 Days")
              "ledger -f %(ledger-file) bal expenses --sort total -p 'last 7 days' --invert"

              (separator)
              (paragraph "Skim the totals below, which are tallied against my budget.
- Am I meeting my budget?
- If not, what are the areas that need improvement?")

              (header-1 "Budget Last 7 Days")
              "ledger -f %(ledger-file) bal expenses --sort total -p 'last 7 days' --invert --budget"
              (header "Budget Last 30 Days")
              "ledger -f %(ledger-file) bal expenses --sort total -p 'last 30 days' --invert --budget"
              (header "Budget Since Payday")
              "ledger -f %(ledger-file) bal expenses --sort total -b %(last-payday) --invert --budget"
              (header "Budget Last Pay Period")
              "ledger -f %(ledger-file) bal expenses --sort total -p %(prev-pay-period) --invert --budget"

              (separator)
              (paragraph "The payees below are organised by total spending against the budget.
- How do my expenses compare to last month?
- Any opportunity for savings here?")

              (header-1 "Budget Last 7 Days, By Payee")
              "ledger -f %(ledger-file) reg expenses --by-payee --sort total -p 'last 7 days' --invert --budget"
              (header "Budget Last 30 Days, By Payee")
              "ledger -f %(ledger-file) reg expenses --by-payee --sort total -p 'last 30 days' --invert --budget"

              (separator)
              (paragraph "Read through the payees below from my checking account. Any spending patterns here that could be budgeted?")
              "ledger -f %(ledger-file) reg checking --by-payee --sort total -p 'last 7 days' --invert"))

            (expenses
             (list
              (header-1 "Expenses For Week")
              "ledger -f %(ledger-file) bal expenses -p 'this week' --invert"
              (header "Expenses For Month")
              "ledger -f %(ledger-file) bal expenses -p 'this month' --invert"
              (header "Expenses Since Payday")
              "ledger -f %(ledger-file) bal expenses -b %(last-payday) --invert"
              (header "Expenses Previous Pay Period")
              "ledger -f %(ledger-file) bal expenses -p %(prev-pay-period) --invert")))

        (setq ledger-reports
              `(("weekly review" ,(report-from-list weekly-review))
                ("expenses" ,(report-from-list expenses))
                ("assets" "ledger -f %(ledger-file) bal assets")
                ("balance" "ledger -f %(ledger-file) bal")
                ("reg this week" "ledger -f %(ledger-file) reg checking -p 'this week' --invert")
                ("reg this month" "ledger -f %(ledger-file) reg checking -p 'this month' --invert")
                ("reg since payday" "ledger -f %(ledger-file) reg checking -b %(last-payday) --invert")
                ("reg previous pay period" "ledger -f %(ledger-file) reg checking -p %(prev-pay-period) --invert")))))))

(defun cb-ledger/init-cb-ledger-format ()
  (use-package cb-ledger-format
    :after ledger-mode
    :config
    (define-key ledger-mode-map (kbd "M-q") #'cb-ledger-format-buffer)))
