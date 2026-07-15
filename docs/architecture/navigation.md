# Navigation architecture

## Authority modes

Every durable navigation surface is assembled in the configured app composition root. This includes ordinary and fullscreen pages, sidebar layouts, bottom navigation, and navigation rail. These are app-shell variants, not separate architecture models.

The default `bloc_projection` mode separates authority from projection:

```text
feature action -> feature-owned navigation port -> app/navigation Bloc
                                                     |
                                                     v
                                              state + history
                                                     |
                                                     v
                                       app/router page + URL projection
```

The navigation Bloc, its state, and history live under `app/navigation`. Code under `app/navigation` does not import or call GoRouter, even when a configured glob accidentally overlaps `router_paths`. Code under `app/router` observes navigation state and projects it to pages, URLs, redirects, and route-scoped providers.

Projects may explicitly choose `authority: router`. In that mode the configured router owns location and history directly. Feature-owned ports, app-level implementations, composition placement, and provider lifetime rules do not change.

## Feature and app responsibilities

A feature declares the smallest useful navigation port in its presentation layer:

```dart
abstract interface class CatalogNavigation {
  void openProduct(String productId);
  void back();
}
```

Feature widgets receive this port and send typed intent. They do not import a router package, construct page routes, create another page/screen, or call durable `Navigator` methods.

The app layer implements the port. In `bloc_projection`, the implementation converts calls into navigation Bloc events. In `router` mode, it delegates to the configured router authority. Arguments stay typed until the app composition layer maps them to route data.

Durable Back is also an authority intent because it changes route history. `Navigator.pop` and `Navigator.maybePop` are reserved for transient UI owned by the current page, such as a dialog, bottom sheet, popup menu, or local overlay.

## Page and provider composition

Project-owned types declared in configured page/screen globs may be created only in `composition_paths`. App roots, route/page factories, and app navigation shells are typical composition locations. An `IndexedStack` used by bottom navigation or a sidebar therefore belongs in app composition, not inside feature UI.

`BlocProvider`, `BlocProvider.value`, and `MultiBlocProvider` follow the same placement rule. Feature pages consume Cubits/Blocs that composition has already provided. DI may register Cubit factories under `app/di`; registration is not widget-provider placement.

Use `BlocProvider(create: ...)` when composition owns a new instance. Use `BlocProvider.value(value: existing)` only to expose an existing instance. Creating a Cubit or Bloc directly in the `value` argument gives the provider the wrong disposal semantics and is always rejected.

## Configuration

```yaml
architecture:
  navigation:
    authority: bloc_projection # bloc_projection | router

    composition_paths:
      - lib/main.dart
      - lib/app/app.dart
      - lib/app/router/**
      - lib/app/navigation/**

    router_paths:
      - lib/main.dart
      - lib/app/app.dart
      - lib/app/router/**

    authority_paths:
      - lib/app/navigation/**

    router_packages:
      - go_router

    provider_constructors:
      - BlocProvider
      - MultiBlocProvider

    page_path_globs:
      - lib/features/*/presentation/pages/**
      - lib/features/*/presentation/screens/**

    page_type_suffixes:
      - Page
      - Screen
```

Defaults are derived from `project.lib_root`, `project.app_root`, and `project.feature_root`. `router_paths` must be non-empty in both modes; `authority_paths` must be non-empty in `bloc_projection`. Lists must contain non-empty strings. Tests and integration tests are outside the placement scan.

## Static enforcement

The architecture command blocks:

- configured router-package imports outside `router_paths`;
- router dependencies in `bloc_projection` authority paths;
- durable `Navigator`/GoRouter calls and Flutter route construction outside `router_paths`;
- project-owned Page/Screen construction outside `composition_paths`;
- configured Bloc provider construction outside `composition_paths`;
- direct Cubit/Bloc creation inside `BlocProvider.value`.

`BlocBuilder`, `BlocListener`, `BlocSelector`, and reading an existing Cubit from `BuildContext` remain valid in feature UI. Navigation violations use the architecture baseline, exceptions, JSON output, and the common `verify` command.

## Required agent review

Static syntax checks cannot prove behavioral ownership. Review every navigation change for all of the following:

- only the configured authority stores route state/history;
- no other Cubit hides a parallel navigation stack;
- allowed `Navigator.pop`/`maybePop` calls close transient UI only;
- each user action maps to the correct typed navigation intent;
- Cubit lifetime, factory/singleton choice, and route arguments are correct;
- every page receives all required Cubits/Blocs;
- deep links, browser history, restoration, and system Back behave correctly;
- navigation is not hidden behind a custom wrapper, barrel re-export, callback, or dynamic call.

These remain checklist-only. Do not add heuristic warnings or false-positive hard failures for them.
