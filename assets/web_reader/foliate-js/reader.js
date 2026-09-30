import './view.js'
import { createTOCView } from './ui/tree.js'
import { Overlayer } from './overlayer.js'

const getCSS = ({ spacing, justify, hyphenate }) => `
    @namespace epub "http://www.idpf.org/2007/ops";
    html {
        color-scheme: light dark;
    }
    /* https://github.com/whatwg/html/issues/5426 */
    @media (prefers-color-scheme: dark) {
        a:link {
            color: lightblue;
        }
    }
    p, li, blockquote, dd {
        line-height: ${spacing};
        text-align: ${justify ? 'justify' : 'start'};
        -webkit-hyphens: ${hyphenate ? 'auto' : 'manual'};
        hyphens: ${hyphenate ? 'auto' : 'manual'};
        -webkit-hyphenate-limit-before: 3;
        -webkit-hyphenate-limit-after: 2;
        -webkit-hyphenate-limit-lines: 2;
        hanging-punctuation: allow-end last;
        widows: 2;
    }
    /* prevent the above from overriding the align attribute */
    [align="left"] { text-align: left; }
    [align="right"] { text-align: right; }
    [align="center"] { text-align: center; }
    [align="justify"] { text-align: justify; }

    pre {
        white-space: pre-wrap !important;
    }
    aside[epub|type~="endnote"],
    aside[epub|type~="footnote"],
    aside[epub|type~="note"],
    aside[epub|type~="rearnote"] {
        display: none;
    }
`

const $ = document.querySelector.bind(document)

const locales = 'en'
const percentFormat = new Intl.NumberFormat(locales, { style: 'percent' })
const listFormat = new Intl.ListFormat(locales, { style: 'short', type: 'conjunction' })

const formatLanguageMap = x => {
    if (!x) return ''
    if (typeof x === 'string') return x
    const keys = Object.keys(x)
    return x[keys[0]]
}

const formatOneContributor = contributor => typeof contributor === 'string'
    ? contributor : formatLanguageMap(contributor?.name)

const formatContributor = contributor => Array.isArray(contributor)
    ? listFormat.format(contributor.map(formatOneContributor))
    : formatOneContributor(contributor)

class Reader {
    #tocView
    style = {
        spacing: 1.4,
        justify: true,
        hyphenate: true,
        fontSize: 18,
        theme: 'light',
    }
    flow = 'paginated'
    annotations = new Map()
    annotationsByValue = new Map()
    searchRequestId = 0
    closeSideBar() {
        $('#dimming-overlay').classList.remove('show')
        $('#side-bar').classList.remove('show')
    }
    constructor() {
        try {
            const saved = JSON.parse(localStorage.getItem('hyesread:reader-settings') || '{}')
            const fontSize = Number(saved.style?.fontSize)
            const spacing = Number(saved.style?.spacing)
            this.style = {
                ...this.style,
                ...(Number.isFinite(fontSize) ? { fontSize: Math.min(32, Math.max(14, fontSize)) } : {}),
                ...(Number.isFinite(spacing) ? { spacing: Math.min(2.2, Math.max(1.2, spacing)) } : {}),
                ...(['light', 'sepia', 'dark'].includes(saved.style?.theme) ? { theme: saved.style.theme } : {}),
            }
            this.flow = saved.flow === 'scrolled' ? 'scrolled' : 'paginated'
        } catch {}
        $('#font-size').value = this.style.fontSize
        $('#line-spacing').value = this.style.spacing
        $('#reading-flow').value = this.flow
        $('#reading-theme').value = this.style.theme
        $('#side-bar-button').addEventListener('click', () => {
            $('#dimming-overlay').classList.add('show')
            $('#side-bar').classList.add('show')
        })
        $('#dimming-overlay').addEventListener('click', () => this.closeSideBar())

        $('#menu-button > button').addEventListener('click', () =>
            $('#reader-settings').classList.toggle('show'))
        $('#font-size').addEventListener('input', event => {
            this.style.fontSize = Number(event.target.value)
            this.applyStyles()
            this.saveSettings()
        })
        $('#line-spacing').addEventListener('input', event => {
            this.style.spacing = Number(event.target.value)
            this.applyStyles()
            this.saveSettings()
        })
        $('#reading-flow').addEventListener('change', event => {
            this.flow = event.target.value
            this.view?.renderer.setAttribute('flow', this.flow)
            this.saveSettings()
        })
        $('#reading-theme').addEventListener('change', event => {
            this.style.theme = event.target.value
            this.applyStyles()
            this.saveSettings()
        })
        $('#search-form').addEventListener('submit', event => {
            event.preventDefault()
            void this.search($('#search-query').value.trim())
        })
    }
    async open(file) {
        this.view = document.createElement('foliate-view')
        document.body.append(this.view)
        await this.view.open(file)
        this.view.renderer.setAttribute('flow', this.flow)
        this.view.addEventListener('load', this.#onLoad.bind(this))
        this.view.addEventListener('relocate', this.#onRelocate.bind(this))

        const { book } = this.view
        book.transformTarget?.addEventListener('data', ({ detail }) => {
            detail.data = Promise.resolve(detail.data).catch(e => {
                console.error(new Error(`Failed to load ${detail.name}`, { cause: e }))
                return ''
            })
        })
        this.applyStyles()
        this.view.renderer.next()

        $('#header-bar').style.visibility = 'visible'
        $('#nav-bar').style.visibility = 'visible'
        $('#left-button').addEventListener('click', () => this.view.goLeft())
        $('#right-button').addEventListener('click', () => this.view.goRight())

        const slider = $('#progress-slider')
        slider.dir = book.dir
        slider.addEventListener('input', e =>
            this.view.goToFraction(parseFloat(e.target.value)))
        for (const fraction of this.view.getSectionFractions()) {
            const option = document.createElement('option')
            option.value = fraction
            $('#tick-marks').append(option)
        }

        document.addEventListener('keydown', this.#handleKeydown.bind(this))

        const title = formatLanguageMap(book.metadata?.title) || 'Untitled Book'
        document.title = title
        $('#side-bar-title').innerText = title
        $('#side-bar-author').innerText = formatContributor(book.metadata?.author)
        Promise.resolve(book.getCover?.())?.then(blob =>
            blob ? $('#side-bar-cover').src = URL.createObjectURL(blob) : null)

        const toc = book.toc
        if (toc) {
            this.#tocView = createTOCView(toc, href => {
                this.view.goTo(href).catch(e => console.error(e))
                this.closeSideBar()
            })
            $('#toc-view').append(this.#tocView.element)
        }

        // load and show highlights embedded in the file by Calibre
        const bookmarks = await book.getCalibreBookmarks?.()
        if (bookmarks) {
            const { fromCalibreHighlight } = await import('./epubcfi.js')
            for (const obj of bookmarks) {
                if (obj.type === 'highlight') {
                    const value = fromCalibreHighlight(obj)
                    const color = obj.style.which
                    const note = obj.notes
                    const annotation = { value, color, note }
                    const list = this.annotations.get(obj.spine_index)
                    if (list) list.push(annotation)
                    else this.annotations.set(obj.spine_index, [annotation])
                    this.annotationsByValue.set(value, annotation)
                }
            }
        }
        this.view.addEventListener('create-overlay', e => {
            const { index } = e.detail
            const list = this.annotations.get(index)
            if (list) for (const annotation of list)
                this.view.addAnnotation(annotation).catch(error => console.error(error))
        })
        this.view.addEventListener('draw-annotation', e => {
            const { draw, annotation } = e.detail
            draw(Overlayer.highlight, { color: annotation.color || '#facc15' })
        })
        this.view.addEventListener('show-annotation', e => {
            const annotation = this.annotationsByValue.get(e.detail.value)
            if (annotation) parent.postMessage({
                type: 'hyesread:annotation-open',
                annotation: { value: annotation.value, text: annotation.note || '' },
            }, '*')
        })
    }
    applyStyles() {
        const themes = {
            light: ['#fff', '#202124'],
            sepia: ['#f4ecd8', '#433b30'],
            dark: ['#181818', '#d8d2c8'],
        }
        const [background, color] = themes[this.style.theme] || themes.light
        this.view?.renderer.setStyles?.(`${getCSS(this.style)}\nhtml { background: ${background}; color: ${color}; } body { font-size: ${this.style.fontSize}px !important; }`)
        document.body.style.background = background
        document.body.style.color = color
    }
    saveSettings() {
        try {
            localStorage.setItem('hyesread:reader-settings', JSON.stringify({ style: this.style, flow: this.flow }))
        } catch (error) {
            console.error('无法保存阅读设置', error)
        }
    }
    async search(query) {
        const requestId = ++this.searchRequestId
        const status = $('#search-status')
        const results = $('#search-results')
        results.replaceChildren()
        if (!query) {
            status.textContent = ''
            return
        }
        status.textContent = '正在搜索'
        const matches = []
        try {
            this.view.clearSearch()
            if (this.view.book.searchText) {
                const pdfMatches = await this.view.book.searchText(query)
                if (requestId !== this.searchRequestId) return
                for (const item of pdfMatches) {
                    const before = item.text.slice(Math.max(0, item.start - 40), item.start)
                    const match = item.text.slice(item.start, item.start + item.length)
                    const after = item.text.slice(item.start + item.length, item.start + item.length + 80)
                    const button = document.createElement('button')
                    button.type = 'button'
                    button.className = 'search-result'
                    button.append(document.createTextNode(`第 ${item.index + 1} 页 · ${before}`))
                    const mark = document.createElement('mark')
                    mark.textContent = match
                    button.append(mark, document.createTextNode(after))
                    button.addEventListener('click', () => this.view.goTo(JSON.stringify({ pageIndex: item.index })))
                    results.append(button)
                }
                status.textContent = `${pdfMatches.length} 处`
                if (!pdfMatches.length) status.textContent = '未找到'
                return
            }
            for await (const item of this.view.search({ query, matchCase: false })) {
                if (requestId !== this.searchRequestId) break
                if (typeof item.progress === 'number') {
                    status.textContent = `正在搜索 ${Math.round(item.progress * 100)}%`
                    await new Promise(requestAnimationFrame)
                    continue
                }
                if (item === 'done') continue
                if (item.subitems) matches.push(...item.subitems)
                else if (item.cfi) matches.push(item)
                if (matches.length >= 500) {
                    matches.length = 500
                    break
                }
            }
            if (requestId !== this.searchRequestId) return
            for (const item of matches) {
                const button = document.createElement('button')
                button.type = 'button'
                button.className = 'search-result'
                const excerpt = item.excerpt || {}
                button.append(document.createTextNode(excerpt.pre || ''))
                const mark = document.createElement('mark')
                mark.textContent = excerpt.match || query
                button.append(mark, document.createTextNode(excerpt.post || ''))
                button.addEventListener('click', () => this.view.goTo(item.cfi))
                results.append(button)
            }
            status.textContent = matches.length === 500 ? '显示前 500 处' : `${matches.length} 处`
        } catch (error) {
            status.textContent = error?.message || String(error)
        }
    }
    #handleKeydown(event) {
        const k = event.key
        if (k === 'ArrowLeft' || k === 'h') this.view.goLeft()
        else if(k === 'ArrowRight' || k === 'l') this.view.goRight()
    }
    async addAnnotation(annotation) {
        const { index } = await this.view.addAnnotation(annotation)
        const list = this.annotations.get(index) ?? []
        if (!list.some(item => item.value === annotation.value)) list.push(annotation)
        this.annotations.set(index, list)
        this.annotationsByValue.set(annotation.value, annotation)
        parent.postMessage({ type: 'hyesread:annotation-added', value: annotation.value }, '*')
    }
    async removeAnnotation(value) {
        const annotation = this.annotationsByValue.get(value)
        if (!annotation) return
        await this.view.deleteAnnotation(annotation)
        this.annotationsByValue.delete(value)
        for (const [index, list] of this.annotations)
            this.annotations.set(index, list.filter(item => item.value !== value))
    }
    #onLoad({ detail: { doc, index } }) {
        doc.addEventListener('hyesread:pdf-rendered', () => {
            if (!doc.querySelector('.textLayer')) return
            for (const annotation of this.annotations.get(index) ?? [])
                this.view.addAnnotation(annotation).catch(error => console.error(error))
        })
        doc.addEventListener('keydown', this.#handleKeydown.bind(this))
        const reportSelection = () => {
            const selection = doc.getSelection()
            if (!selection || selection.isCollapsed || !selection.toString().trim()) return
            try {
                parent.postMessage({
                    type: 'hyesread:selection',
                    selection: { value: this.view.getCFI(index, selection.getRangeAt(0)), text: selection.toString().trim() },
                }, '*')
            } catch (error) { console.error('Could not capture selected passage', error) }
        }
        doc.addEventListener('selectionchange', reportSelection)
        doc.addEventListener('mouseup', reportSelection)
        doc.addEventListener('keyup', reportSelection)
    }
    #onRelocate({ detail }) {
        const { fraction, location, tocItem, pageItem } = detail
        const percent = percentFormat.format(fraction)
        const loc = pageItem
            ? `Page ${pageItem.label}`
            : `Loc ${location.current}`
        const slider = $('#progress-slider')
        slider.style.visibility = 'visible'
        slider.value = fraction
        slider.title = `${percent} · ${loc}`
        if (tocItem?.href) this.#tocView?.setCurrentHref?.(tocItem.href)
    }
}

const showError = error => {
    let target = $('#drop-target')
    if (!target) {
        target = document.createElement('div')
        target.id = 'drop-target'
        target.className = 'filter'
        target.innerHTML = '<div><h1></h1><p></p></div>'
    }
    if (!target.isConnected) document.body.append(target)
    target.style.visibility = 'visible'
    target.querySelector('h1').textContent = '无法打开这本书'
    target.querySelector('p').textContent = error?.message || String(error)
    console.error(error)
    parent.postMessage({ type: 'hyesread:error', message: error?.message || String(error) }, '*')
}

const open = async file => {
    $('#drop-target').remove()
    const reader = new Reader()
    globalThis.reader = reader
    try { await reader.open(file) } catch (error) { showError(error); return }
    reader.view.addEventListener('relocate', ({ detail }) => parent.postMessage({
        type: 'hyesread:relocate',
        location: { fraction: detail.fraction, location: detail.location?.current, href: detail.tocItem?.href, chapter: detail.tocItem?.label },
    }, '*'))
    parent.postMessage({ type: 'hyesread:ready' }, '*')
}

const dragOverHandler = e => e.preventDefault()
const dropHandler = e => {
    e.preventDefault()
    const item = Array.from(e.dataTransfer.items)
        .find(item => item.kind === 'file')
    if (item) {
        const entry = item.webkitGetAsEntry()
        open(entry.isFile ? item.getAsFile() : entry).catch(e => console.error(e))
    }
}
const dropTarget = $('#drop-target')
dropTarget.addEventListener('drop', dropHandler)
dropTarget.addEventListener('dragover', dragOverHandler)

$('#file-input').addEventListener('change', e =>
    open(e.target.files[0]).catch(e => console.error(e)))
$('#file-button').addEventListener('click', () => $('#file-input').click())

const params = new URLSearchParams(location.search)
const url = params.get('url')
addEventListener('message', event => {
    if (event.source !== parent || !event.data) return
    if (event.data.type === 'hyesread:open-file' && event.data.file)
        open(event.data.file).catch(showError)
    if (event.data.type === 'hyesread:restore' && event.data.location?.fraction != null)
        globalThis.reader?.view?.goToFraction(event.data.location.fraction).catch(console.error)
    if (event.data.type === 'hyesread:annotations' && Array.isArray(event.data.annotations)) {
        const current = globalThis.reader
        if (!current?.view) return
        for (const annotation of event.data.annotations)
            current.addAnnotation(annotation).catch(error => parent.postMessage({
                type: 'hyesread:annotation-error', value: annotation.value, message: error?.message || String(error),
            }, '*'))
    }
    if (event.data.type === 'hyesread:add-annotation' && event.data.annotation)
        globalThis.reader?.addAnnotation(event.data.annotation).catch(error => parent.postMessage({
            type: 'hyesread:annotation-error', value: event.data.annotation.value, message: error?.message || String(error),
        }, '*'))
    if (event.data.type === 'hyesread:remove-annotation' && typeof event.data.value === 'string')
        globalThis.reader?.removeAnnotation(event.data.value).catch(error => parent.postMessage({
            type: 'hyesread:annotation-error', value: event.data.value, message: error?.message || String(error),
        }, '*'))
    if (event.data.type === 'hyesread:show-annotation' && typeof event.data.value === 'string')
        globalThis.reader?.view?.showAnnotation({ value: event.data.value }).catch(console.error)
    if (event.data.type === 'hyesread:toggle-settings') {
        $('#reader-search').classList.remove('show')
        $('#reader-settings').classList.toggle('show')
    }
    if (event.data.type === 'hyesread:toggle-search') {
        const panel = $('#reader-search')
        $('#reader-settings').classList.remove('show')
        panel.classList.toggle('show')
        if (panel.classList.contains('show')) $('#search-query').focus()
    }
})
if (url) open(url).catch(e => console.error(e))
else dropTarget.style.visibility = 'visible'
