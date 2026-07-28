import QtQuick

// Static wallpaper / lock backdrop catalogs (flat shared package).
QtObject {
  id: catalog
  readonly property var lockBackgroundModes: [
    {
      id: "match",
      label: "Match"
    },
    {
      id: "color",
      label: "Color"
    },
    {
      id: "image",
      label: "Image"
    },
    {
      id: "daily",
      label: "Daily"
    },
    {
      id: "video",
      label: "Video"
    },
    {
      id: "reactive",
      label: "Animated"
    }
  ]


  readonly property var wallpaperKinds: [
    {
      id: "color",
      label: "Color"
    },
    {
      id: "image",
      label: "Image"
    },
    {
      id: "daily",
      label: "Daily"
    },
    {
      id: "video",
      label: "Video"
    },
    {
      id: "reactive",
      label: "Animated"
    }
  ]


  readonly property var wallpaperColors: [
    {
      id: "slate",
      label: "Slate",
      color: "#0f1419"
    },
    {
      id: "ink",
      label: "Ink",
      color: "#0a0e14"
    },
    {
      id: "navy",
      label: "Navy",
      color: "#0c1a2e"
    },
    {
      id: "forest",
      label: "Forest",
      color: "#0f1f18"
    },
    {
      id: "plum",
      label: "Plum",
      color: "#1a1224"
    },
    {
      id: "charcoal",
      label: "Charcoal",
      color: "#1c1c1e"
    }
  ]


  readonly property var wallpaperReactives: [
    {
      id: "drift",
      label: "Drift",
      hint: "Slow shifting gradient"
    },
    {
      id: "pulse",
      label: "Pulse",
      hint: "Accent wash follows playback level"
    },
    {
      id: "orbit",
      label: "Orbit",
      hint: "Soft accent motion"
    },
    {
      id: "aurora",
      label: "Aurora",
      hint: "Layered color bands"
    },
    {
      id: "beacon",
      label: "Beacon",
      hint: "Soft breathing glow"
    }
  ]


  readonly property var wallpaperDailyProviders: [
    {
      id: "bing",
      label: "Bing",
      hint: "Windows-style daily photo · no key",
      needsKey: false
    },
    {
      id: "unsplash",
      label: "Unsplash",
      hint: "Random landscape · requires Access Key",
      needsKey: true
    },
    {
      id: "custom",
      label: "Custom",
      hint: "Your feed URL · optional API key",
      needsKey: false
    }
  ]


  readonly property var wallpaperDailyAuthModes: [
    {
      id: "none",
      label: "None"
    },
    {
      id: "bearer",
      label: "Bearer"
    },
    {
      id: "client-id",
      label: "Client-ID"
    },
    {
      id: "query",
      label: "Query"
    }
  ]

}
