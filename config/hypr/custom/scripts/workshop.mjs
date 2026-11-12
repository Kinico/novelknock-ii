#!/usr/bin/env node
// Steam Workshop for the Super+Z picker (same approach as the wallpaperx app: Steamworks through
// your running Steam client, so no API key is needed and subscribing downloads right away).
//   node workshop.mjs status
//   node workshop.mjs query <trend|votes|subscriptions|date|updated> <page> <all|Scene|Video|Web> <all|Everyone|Questionable|Mature> [search words]
//   node workshop.mjs subscribe <id>     prints progress lines until the wallpaper is downloaded
//   node workshop.mjs unsubscribe <id>
// Needs: Node.js, Steam running and logged in, and steamworks.js installed by workshop-setup.sh.
import { createRequire } from 'node:module'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const APP = 431960 // Wallpaper Engine
const MODULE = process.env.NK_STEAMWORKS
    || path.join(os.homedir(), '.local/share/novelknock-workshop/node_modules/steamworks.js')
const SORT = { trend: 3, votes: 10, subscriptions: 12, date: 1, updated: 19 }
const TEXT_SEARCH = 11
const READY_TO_USE = 2
const STATE_INSTALLED = 4, STATE_DOWNLOADING = 16, STATE_PENDING = 32

const out = (o) => process.stdout.write(JSON.stringify(o, (k, v) => typeof v === 'bigint' ? v.toString() : v) + '\n')
const done = (o) => { if (o) out(o); setTimeout(() => process.exit(0), 50) }

function workshopDirs() {
    const steam = path.join(os.homedir(), '.local/share/Steam')
    const libs = [path.join(steam, 'steamapps')]
    try {
        const vdf = fs.readFileSync(path.join(steam, 'steamapps/libraryfolders.vdf'), 'utf8')
        for (const m of vdf.matchAll(/"path"\s*"([^"]*)"/g)) libs.push(path.join(m[1], 'steamapps'))
    } catch {}
    return [...new Set(libs)].map((l) => path.join(l, 'workshop/content', String(APP))).filter((d) => fs.existsSync(d))
}
const DIRS = workshopDirs()
const installedDir = (id) => {
    for (const d of DIRS) if (fs.existsSync(path.join(d, id, 'project.json'))) return path.join(d, id)
    return ''
}
const lower = (tags) => new Set(tags.map((t) => t.trim().toLowerCase()))
const typeOf = (tags) => { const t = lower(tags); for (const k of ['Scene', 'Video', 'Web', 'Application']) if (t.has(k.toLowerCase())) return k; return '' }
const ratingOf = (tags) => { const t = lower(tags); for (const k of ['Mature', 'Questionable', 'Everyone']) if (t.has(k.toLowerCase())) return k; return '' }

let sw, client
try {
    sw = createRequire(import.meta.url)(MODULE)
} catch {
    done({ error: 'missing', message: 'Workshop support is not installed yet. Run workshop-setup.sh.' })
}
if (sw) {
    try {
        client = sw.init(APP)
    } catch {
        done({ error: 'steam', message: 'Open Steam (and log in) to browse the Workshop.' })
    }
}

async function main() {
    const [cmd, ...a] = process.argv.slice(2)
    if (cmd === 'status') return done({ ok: true })

    if (cmd === 'query') {
        const sort = a[0] || 'trend'
        const page = Math.max(1, parseInt(a[1] || '1', 10) || 1)
        const type = a[2] || 'all'
        const rating = a[3] || 'all'
        const search = a.slice(4).join(' ').trim()
        const queryType = search ? TEXT_SEARCH : (SORT[sort] ?? 3)
        const required = []
        if (type !== 'all') required.push(type)
        if (rating !== 'all') required.push(rating)
        const res = await client.workshop.getAllItems(page, queryType, READY_TO_USE, APP, APP, {
            searchText: search || undefined,
            matchAnyTag: false,
            requiredTags: required.length ? required : undefined,
            excludedTags: type === 'all' ? ['Application'] : undefined, // can not run on Linux
            rankedByTrendDays: queryType === 3 ? 30 : undefined,
            includeMetadata: true,
            includeLongDescription: false,
            includeAdditionalPreviews: false,
        })
        const items = (res.items || []).filter(Boolean).map((it) => {
            const id = it.publishedFileId.toString()
            return {
                id,
                title: it.title || id,
                preview: it.previewUrl || '',
                type: typeOf(it.tags || []),
                rating: ratingOf(it.tags || []),
                votes: it.numUpvotes || 0,
                installed: installedDir(id),
            }
        }).filter((i) => i.type !== 'Application')
        return done({
            items,
            page,
            total: Math.min(res.totalResults || 0, 50000),
            hasNext: page * (res.returnedResults || 0) < (res.totalResults || 0),
        })
    }

    if (cmd === 'subscribe') {
        const idStr = String(a[0] || '').replace(/\D/g, '')
        if (!idStr) return done({ error: 'id' })
        const id = BigInt(idStr)
        await client.workshop.subscribe(id)
        client.workshop.download(id, true)
        const start = Date.now()
        let last = -1
        while (Date.now() - start < 15 * 60 * 1000) {
            const state = client.workshop.state(id)
            const dl = client.workshop.downloadInfo(id)
            const folder = installedDir(idStr) || client.workshop.installInfo(id)?.folder || ''
            const busy = state & (STATE_DOWNLOADING | STATE_PENDING)
            if ((state & STATE_INSTALLED) && !busy && folder && fs.existsSync(path.join(folder, 'project.json'))) {
                return done({ id: idStr, done: true, folder })
            }
            if (dl && dl.total > 0n) {
                const p = Math.floor(Number(dl.current * 1000n / dl.total)) / 1000
                if (p !== last) { last = p; out({ id: idStr, progress: p }) }
            }
            await new Promise((r) => setTimeout(r, 500))
        }
        return done({ id: idStr, error: 'timeout', message: 'Still downloading in Steam, check again later.' })
    }

    if (cmd === 'unsubscribe') {
        const idStr = String(a[0] || '').replace(/\D/g, '')
        await client.workshop.unsubscribe(BigInt(idStr))
        return done({ id: idStr, removed: true })
    }

    done({ error: 'usage' })
}

if (client) main().catch((e) => done({ error: 'failed', message: String(e?.message || e) }))
