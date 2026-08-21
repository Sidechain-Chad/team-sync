---
title: Due dates and start dates
category: Cards
position: 3
---

## Set a due date

Open the card and click the clock icon under **Due date**. Pick a quick preset (**Today 5pm**, **Tomorrow 9am**, **Next week**) or set an exact date and time yourself.

Once set, the due date shows as a colored pill on the card, both on the board tile and inside the modal. The color tells you the status at a glance: overdue, due soon, upcoming, or complete.

## Add a start date

In the same popover, set a **Start date**. TeamSync validates that it falls on or before the due date; it won't let you set a start date after the due date.

A card with both dates set shows as a date range rather than a single point, and that range is what [the planner](/help/planner-and-map) uses to draw a bar spanning several days on the calendar, instead of a chip that only appears on the due date itself.

## Mark complete from the date popover

The same popover has a **Mark as complete** checkbox, a shortcut so you don't have to close it and click the completion circle separately.

## Remove a due date

Open the popover and click **Remove**. This clears both the due and start date together; there's no way to remove one but not the other from this control.

## Due-soon reminders

TeamSync can notify people when a card they're on is coming due. In the seeded development environment and in a deployment without the background worker enabled, this scan never runs, so due-soon notifications won't arrive even though the preference for them exists. See [Watching and notifications](/help/watching-and-notifications).
