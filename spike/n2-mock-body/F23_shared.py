"""Writes F2's and F3's shared variant (`s`): today's generated file (`b/stored`) with the mock body replaced."""
import os
here = os.path.dirname(os.path.abspath(__file__))

def replace(fixture, opening, closing, body):
    lines = open(os.path.join(here, fixture, "b/stored/App.swift.txt")).read().split("\n")
    start = next(i for i, l in enumerate(lines) if l.strip() == opening) + 1
    end = next(i for i, l in enumerate(lines) if l.strip() == closing and i > start) + 1
    lines[start:end] = body.split("\n")
    open(os.path.join(here, fixture, "s/App/Generated/App.swift"), "w").write("\n".join(lines))

replace("F2", ") -> Home {", "return Home(screen: screen)", '''        // One function per key. Screen's places read different configurations (the first `screen`, a reopened one none),
        // so its configuration is a parameter; every Step reads `screen.stepBuilder`, so Step captures it, as today.
        // `cache` is declared again in every Screen, so Step takes it as a parameter (today's cycle parameter).
        func __safeDI_screen(safeDIOverrides __safeDI_overrides: Screen.SafeDIMockConfiguration?) -> Screen {
            let cache = if let safeDIBuilder = __safeDI_overrides?.cache { safeDIBuilder() } else { Cache() }
            let stepBuilder = Instantiator<Step> {
                __safeDI_stepBuilder(cache: cache)
            }
            return if let safeDIBuilder = __safeDI_overrides?.safeDIBuilder { safeDIBuilder(cache, stepBuilder) } else { Screen(cache: cache, stepBuilder: stepBuilder) }
        }
        func __safeDI_stepBuilder(cache: Cache) -> Step {
            let model = if let safeDIBuilder = safeDIOverrides.screen.stepBuilder.model { safeDIBuilder(cache) } else { Model(cache: cache) }
            let screenBuilder = Instantiator<Screen> {
                __safeDI_screen(safeDIOverrides: nil)
            }
            return if let safeDIBuilder = safeDIOverrides.screen.stepBuilder.safeDIBuilder { safeDIBuilder(model, screenBuilder) } else { Step(model: model, screenBuilder: screenBuilder) }
        }
        let screen: Screen = __safeDI_screen(safeDIOverrides: safeDIOverrides.screen)
        return Home(screen: screen)''')

replace("F3", ") -> App {", "return App(theme: theme, editor: editor)", '''        let theme = if let safeDIBuilder = safeDIOverrides.theme { safeDIBuilder() } else { Theme() }
        // One function per key, at the body's top level. Every place of each type reads the same configuration (today's
        // closing call re-enters `__safeDI_editor`), so each captures it; `theme` is declared again in every Preview, so
        // Editor takes it as a parameter (today's cycle parameter).
        func __safeDI_editor(theme: Theme) -> Editor {
            let previewBuilder = Instantiator<Preview>(__safeDI_previewBuilder)
            let toolbar = if let safeDIBuilder = safeDIOverrides.editor.toolbar { safeDIBuilder(theme) } else { Toolbar(theme: theme) }
            return if let safeDIBuilder = safeDIOverrides.editor.safeDIBuilder { safeDIBuilder(previewBuilder, toolbar) } else { Editor(previewBuilder: previewBuilder, toolbar: toolbar) }
        }
        func __safeDI_previewBuilder() -> Preview {
            let theme = if let safeDIBuilder = safeDIOverrides.editor.previewBuilder.theme { safeDIBuilder() } else { Theme() }
            let editor = LazilyInstantiated<Editor> {
                __safeDI_editor(theme: theme)
            }
            return if let safeDIBuilder = safeDIOverrides.editor.previewBuilder.safeDIBuilder { safeDIBuilder(theme, editor) } else { Preview(theme: theme, editor: editor) }
        }
        let editor: Editor = __safeDI_editor(theme: theme)
        return App(theme: theme, editor: editor)''')
