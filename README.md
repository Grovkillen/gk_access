# GK Access

GK Access decides who may see what beyond what Redmine's roles cover: information levels with a rank, every role's ceiling, and Private, which works as in Redmine or, where strict is chosen, lets private notes and private issues reach only the one who wrote them. Other GK plugins ask it whether a person sees a level.

## Features

Information levels:

- Levels are data: a key, a rank and a name. A higher rank is more restricted, and whoever sees a level sees every level with a lower rank. The defaults are Open at rank 0, Internal at rank 100 and Sensitive at rank 200, in steps of 100 so that levels can be put between and above them.
- The administrator adds levels and closes them for new things. A level in use is never removed.
- Every role has a ceiling, the highest level it sees. Without a ceiling a role sees the lowest level only. Non member and Anonymous have ceilings like the other roles. The administrator sees every level with a rank.
- Other plugins ask `GkAccess.sees?(user, level, project:)`, `GkAccess.ceiling(user, project)` and `GkAccess.levels`. When the levels cannot be read, or the level asked about is not one of them, `GkAccess.sees?` answers no instead of yes (and writes the failure to the log), so that the plugin that asks hides what it asked about.

Private:

- Two kinds: as in Redmine (the default) and strict. The kind is chosen for private issues and private notes each.
- The administrator chooses the kind for the whole instance on Administration > Levels. A project can choose strict for itself in its settings (the tab Private, with the permission Manage Private); it is never less strict than the instance, and only an administrator makes a project less strict again.
- Before strict is chosen, the page shows how many private notes and issues it concerns and which roles and people lose access. Every change of the kind is an event in GK Records.
- Strictly private is for good. A private issue or note made where strict holds, or private already when strict is chosen there, stays strictly private when the instance or the project goes back to as in Redmine and when the issue moves to another project. A change back holds only for what becomes private after it. Only the author ends it, by making the issue or note not private.
- Whoever would have seen a strictly private issue under Redmine's rules, such as an administrator or a role that sees all issues, is told that the issue exists and is strictly private, never who wrote it, what it says or when. Administration > Levels shows how many strictly private issues and notes each project has.
- An account that is deleted takes what it holds strictly private with it, so that no one else ever sees it. The page that asks before the deletion and the event in GK Records give only how many there are and their anonymous identities (SP-XXXX-XXXX, drawn at random), never a number, project, subject, date or text. With GK Retention only an administrator deletes such an account, and a preservation hold in one of its projects refuses the deletion while it lasts (the account can be locked). Its other private issues and notes go to Anonymous as in Redmine; locking an account is as before.
- With the row The explanation by Private on under Administration > Appearance (off from the start), the user sees which kind holds and who sees what is private: by the check box Private in the issue form, by the check box for private notes, on a private issue and by a private note in the history, with the names of the author, the assignee and the roles that see it.
- Where strict holds, a private note or a private issue reaches only the one who wrote it. The permission View private notes, the roles' issue visibility, the assignment, groups, watchers and the administrator give no access. This holds everywhere Redmine shows a note or an issue: the issue page and its history, lists and queries (last notes, last updated by, filters), search, Atom, the REST API, PDF, mail and mentions, reactions and a note's attachments.
- Where strict holds, only the one who wrote a note or an issue makes it private or not, a note with changes or attachments cannot be made private afterwards, and a private issue cannot be assigned to anyone but its author.
- When the plugin's tables cannot be read (they are missing, for example before the migrations have run, or reading them fails), Private answers as strict everywhere, never as in Redmine, and writes the failure to the log: every private note and private issue reaches only the one who wrote it until the tables can be read again. Nothing is marked strictly private and no event is written on that answer, and the REST API for a project's Private answers that Private cannot be read.
- Whoever has the database can always read it technically.

REST API (with Redmine's REST web service enabled), JSON, by the same rules as the pages and never showing more:

- Administrators: `GET /gk_access/levels.json` and `/gk_access/levels/<id>.json`, `POST /gk_access/levels.json`, `PUT /gk_access/levels/<id>.json` (a level is closed with `"closed": true`) and `DELETE /gk_access/levels/<id>.json` (refused for a default level and a level in use). `GET` and `PUT /gk_access/levels/ceilings.json` (`{ "ceilings": { "<role id>": "<level key>" } }`). `GET` and `PUT /gk_access/levels/private.json` (`{ "private": { "issues": "strict", "notes": "core" } }`; the answer to `GET` also has what becomes strictly private, who loses access and the projects that chose strict). `GET /gk_access/levels/strict_counts.json`: how many strictly private issues and notes each project has, never which.
- Whoever may manage Private in a project, and administrators, as Redmine's project Settings (nothing in an archived or a closed project): `GET` and `PUT /projects/<id>/gk_access/private.json`, the project's own kind, the instance's and what holds. Only an administrator makes a project less strict.
- OAuth (Redmine 6.1 and later): a token reads with the scope "Read levels, ceilings and the kind of Private (API scope)" and changes with "Change levels, ceilings and the kind of Private (API scope)". The scopes only limit a token; who may do something stays the same. In a project a token also needs Manage Private there. The scopes are checked with a GK Compat that has the scope checks, and then an administrator's token needs only the scope; without it, or with an older GK Compat, the scopes are not checked and an administrator's token counts as an administrator only with Redmine's scope Administration, as in Redmine. Sessions and API keys work as before.

## Requirements

- Redmine 6.0.0 or higher.
- Ruby 3.2 or later, the version your Redmine release runs on.
- PostgreSQL.

This plugin is developed and tested on Windows 11 with PostgreSQL only. It may well run on Linux, but that is untested and not supported. The migrations use only ordinary column types, but PostgreSQL is the only database the plugin is tested on.

GK plugins:

- Required: GK Records (`gk_records`): every change of a level, a ceiling or the kind of Private is an event, and so is an existing issue made strictly private or a strictly private issue made not private (an issue created private, a private issue moved into a project where strict holds and a private note have no event of their own); without it levels, ceilings and the kind of Private cannot be changed, and the Configure page says so at the top. GK Core Stuff (`gk_core_stuff`): the tab Private in a project's settings is registered in its register of tabs; without it the tab is not shown and Private cannot be chosen per project. GK GUI Stuff (`gk_gui_stuff`, active): the lock by Private opens in its popover, Delete is in the row's menu in the list of levels, the questions before a level is deleted and before the kind of Private is saved are asked in its box on the page, and it draws the change log on the Configure page. Without it, with an older one or with one that is not active, the pages, the menu item, what GK Access draws on other pages (the explanation by Private, its row under Appearance, the tab Private in a project's settings, the names of the levels under Translations) and the REST API are closed, and the Configure page says what is missing. Protection, traces and the registered permissions hold all the same: a strictly private issue or note still reaches only its author, what becomes private where strict holds is still marked, other plugins' questions about levels are still answered, the events are still written in GK Records: an existing issue made strictly private or its strictly private ended, and what a deleted account took with it. And the permissions stay registered, so a role that is saved meanwhile keeps Manage Private. GK Access has no project module.
- Optional: GK Compat (`gk_compat`): the OAuth scopes of the REST API. GK Fields (`gk_fields`): other languages for the names of the levels the administrator adds. GK People (`gk_people`): while an administrator looks at the pages as a person, nothing of hers that is strictly private is shown. GK Retention (`gk_retention`): an account that holds something strictly private is deleted only by an administrator, and not while a preservation hold lasts in one of the projects concerned. GK Scenarios (`gk_scenarios`): the scenario checks.

## Installation

The plugin directory must be named `gk_access` (it is the plugin id): `plugins/gk_access/`.

1. Unpack the release package into Redmine's `plugins` directory.
2. Run the migrations: `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`
3. Restart Redmine. Private works as in Redmine until strict is chosen.

Uninstall:

1. `bundle exec rake redmine:plugins:migrate NAME=gk_access VERSION=0 RAILS_ENV=production`
2. Remove the `plugins/gk_access` directory and restart Redmine.

Migrating to version 0 removes the plugin's tables and its row in Redmine's settings. Until Redmine is restarted without the plugin, every private note and private issue reaches only the one who wrote it (the tables cannot be read). After that, what was strictly private is private as in Redmine again: the marks are in the plugin's tables, and Redmine's own rules decide who sees a private issue or note.

## Configuration

- Administration > Levels: the levels by rank, every role's ceiling, the kind of Private for the instance, and the projects that chose strict themselves.
- Project > Settings > Private: the project's own kind (the permission Manage Private, which also opens the project's settings; there the role sees only the tabs its permissions allow). The permission is not part of a project module: Private holds whatever modules a project has.

## Changelog

See CHANGELOG.md.

## License

GPL-2.0-or-later, the same license as Redmine. Copyright (C) 2026 Jimmy Westberg. See the LICENSE file for the full text.
