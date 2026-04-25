# TeamSync

A Trello-like project management application built with Rails 7, Hotwire, and Tailwind CSS.

## Features

- **Boards & Lists:** Organize tasks into boards and customizable lists.
- **Drag-and-Drop:** Seamlessly move cards between lists and reorder lists (powered by Stimulus and SortableJS).
- **Rich Cards:** Add descriptions, checklists, attachments, and labels to cards.
- **Collaboration:** Invite other users to your boards.
- **Real-time Updates:** Turbo Streams provide live updates for comments and activities.

## Getting Started

### Prerequisites

- Ruby 3.3.5
- PostgreSQL
- Node.js & Yarn (for assets)

### Setup

1.  **Clone the repository:**
    ```bash
    git clone <repo-url>
    cd team-sync
    ```

2.  **Install dependencies:**
    ```bash
    bundle install
    ```

3.  **Database setup:**
    ```bash
    bin/rails db:prepare
    ```

4.  **Start the development server:**
    ```bash
    bin/dev
    ```

## Testing

Run the test suite with:
```bash
bin/rails test
```

## Linting

This project uses RuboCop for code style enforcement:
```bash
bundle exec rubocop
```
