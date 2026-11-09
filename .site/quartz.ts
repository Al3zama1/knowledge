import { loadQuartzConfig, loadQuartzLayout } from "./quartz/plugins/loader/config-loader"
import { Explorer } from "@quartz-community/explorer"

// Top-level folders in the order you want them in the sidebar
const folderOrder = ["notes", "labs"]

Explorer({
  sortFn: (a, b) => {
    const ai = folderOrder.indexOf(a.displayName.toLowerCase())
    const bi = folderOrder.indexOf(b.displayName.toLowerCase())

    if (ai !== -1 || bi !== -1) {
      if (ai === -1) return 1
      if (bi === -1) return -1
      return ai - bi
    }

    if (a.isFolder === b.isFolder) {
      return a.displayName.localeCompare(b.displayName, undefined, {
        numeric: true,
        sensitivity: "base",
      })
    }
    return a.isFolder ? -1 : 1
  },
})

const config = await loadQuartzConfig()
export default config
export const layout = await loadQuartzLayout()