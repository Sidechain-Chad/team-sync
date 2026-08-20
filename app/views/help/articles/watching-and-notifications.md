---
title: Watching and notifications
category: Collaboration
position: 3
---

Watching widens who gets notified about something, separately from being a member of it. You can watch a card you're not assigned to, or a board you're not otherwise tracking closely, and get notified about activity on it anyway.

## Watch a card

Open the card and click the eye icon next to `⋯`, near the top. Click it again to stop watching. When you're watching a card, it shows a small "watching" indicator on its board tile too, so you don't need to open it to check.

## Watch a board

Open the board menu and choose **Watch board**. Watching a board notifies you when new cards are added to it; it doesn't widen every other notification type to cover the whole board, only that one.

## What you get notified about

TeamSync has nine notification types, each independently switchable in **Account, Settings**: comments on cards you're a member of, being @mentioned, being added to or removed from a card, due dates coming up, and, for anything you're watching, moves, archives, new attachments, and new cards. Turn off what you don't want; the rest keep working.

## The notification badge

Unread notifications show as a count on the bell icon in the top bar, and it updates live: if someone comments on a card while you have TeamSync open elsewhere, the badge changes without a reload. Click the bell to see the list, and **Mark all as read** to clear it in one action.

## Due-soon reminders need the background worker

The "due dates coming up" notification depends on an hourly scan that runs as a background job. If that worker isn't running, which is the case in this deployment because it's a paid Render service that hasn't been enabled, due-soon notifications simply never fire. The preference still exists and can be turned on; it just has nothing to trigger it yet.
