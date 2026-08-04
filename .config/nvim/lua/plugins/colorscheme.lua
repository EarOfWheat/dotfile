return {
    {
        "folke/tokyonight.nvim",
        -- "shaunsingh/nord.nvim",
        -- name = "nord",
        opts = {
            -- style = "night",
            transparent = true,
            styles = {
                sidebars = "transparent",
                keywords = { bold = true },
                functions = { bold = true },
                floats = "transparent",
            },
        },
    },

    {
        "LazyVim/LazyVim",
        opts = {
            colorscheme = "tokyonight",
            -- colorscheme = "nord",
            -- nord_disable_background = true,
            -- nord_cursorline_transparent = true,
            -- nord_enable_sidebar_background = true,
        },
    },
}
