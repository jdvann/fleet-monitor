#!/usr/bin/env python3
"""Set or update security questions for a headscale-admin user."""

import hashlib
import os
import sqlite3
import sys

DB_PATH = os.path.expanduser("~/headscale-admin/headscale_admin.db")

QUESTIONS = [
    "What was the name of your first pet?",
    "What city were you born in?",
    "What is your mother's maiden name?",
    "What was your first car?",
    "What school did you attend in 6th grade?",
    "What is your favorite book?",
    "What was your childhood nickname?",
    "What is the name of your best friend in high school?",
]


def main():
    if len(sys.argv) < 2:
        print("Usage: set_security_questions.py <username>")
        sys.exit(1)

    username = sys.argv[1]
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    user = db.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
    if not user:
        print(f"User '{username}' not found")
        sys.exit(1)

    print(f"\nSetting security questions for: {username}")
    print("Available questions:")
    for i, q in enumerate(QUESTIONS, 1):
        print(f"  {i}. {q}")

    answers = []
    for n in range(1, 4):
        while True:
            try:
                choice = int(input(f"\nQuestion {n} (1-{len(QUESTIONS)}): "))
                if 1 <= choice <= len(QUESTIONS):
                    break
            except ValueError:
                pass
            print("Invalid choice")
        answer = input(f"Answer for '{QUESTIONS[choice-1]}': ").strip()
        if not answer:
            print("Answer cannot be empty")
            sys.exit(1)
        answers.append((QUESTIONS[choice - 1], answer))

    db.execute(
        "UPDATE users SET security_question1=?, security_answer1=?, security_question2=?, security_answer2=?, security_question3=?, security_answer3=? WHERE id=?",
        (answers[0][0], answers[0][1], answers[1][0], answers[1][1], answers[2][0], answers[2][1], user["id"]),
    )
    db.commit()
    db.close()
    print(f"\nSecurity questions set for {username}")


if __name__ == "__main__":
    main()
