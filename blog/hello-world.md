---
title: Hello, Blog World!
date: 2025-06-01
author: Josephine Pfeiffer
tags: [blog, introduction, markdown, static-site, containers]
description: The inaugural post for my new blog
---

After years of publishing on various platforms, I've come full circle and set up a self-hosted blog again! This inaugural post explains why I made the switch and how I built this site.

## Why Medium Isn't Great for Readers

Medium started with good intentions, but it's become increasingly hostile to readers. The constant nag walls asking for subscriptions interrupt the reading experience. Their aggressive email marketing tactics and the limited number of "free" articles create artificial scarcity for content that I want to be freely accessible.

Even worse, Medium's reading experience has deteriorated with floating sidebars, sticky headers, and pop-ups that take up valuable screen real estate. The platform prioritizes its monetization strategy over reader comfort, resulting in slow page loads filled with tracking scripts and analytics.

When readers visit a technical blog, they want the content -- not a battle with the UI.

## The Migration

Migrating my blog was also a convenient chance to evaluate my existing content. Some posts have aged poorly and some simply don't meet my quality standards anymore.

Each article that made it to this blog has been reviewed, updated where necessary, and deemed worthy of preservation. It's liberating to leave behind content that no longer serves its purpose and focus on what truly matters.

## The Technical Setup

Here's the complete structure of my site's repository:

```
.
├── Containerfile           # Multi-stage container build definition
├── blog/                   # Markdown content and templates
│   ├── *.md                # Blog posts in Markdown format
│   ├── images/             # Images used in blog posts
│   ├── index.html          # Main blog index
│   └── template.html       # HTML template for post rendering
├── talks/                  # Conference talks and presentations
│   ├── *.md                # Talk descriptions and metadata
│   ├── slides/             # PDF presentations
│   └── index.html          # Talks listing page
├── scripts/
│   └── blog-build.sh       # Markdown to HTML conversion script
├── index.html              # Homepage with interactive terminal
├── styles.css              # Global styles
├── sw.js                   # Service worker for offline functionality
├── rss.xml                 # RSS feed for the blog
└── sitemap.xml             # Sitemap for SEO
```

The full code is also available on [GitHub](https://github.com/pfeifferj/josiedotlol).

### Content-First Approach

The foundation of this blog is straightforward: content is written in Markdown files, which are then converted to HTML using Pandoc. This approach keeps the focus on writing rather than wrestling with formatting. The separation of content from presentation means I can update the site's design without touching the articles themselves.

Here's what a typical Markdown file looks like:

```md
---
title: Hello, Blog World!
date: 2025-01-05
author: Josephine Pfeiffer
tags: [blog, introduction, markdown, static-site, containers]
description: The inaugural post for my new blog
---

# Hello, Blog World!

After years of publishing on various platforms, I've come full circle...
```

Markdown strikes the perfect balance between readability in its raw form and flexibility for presentation. I can include code blocks with syntax highlighting, images with captions, and mathematical formulas when needed -- all without leaving the comfort of plain text.

### Multi-Stage Container Build

I've set up a multi-stage Docker build that handles the conversion process efficiently:

```dockerfile
# Stage 1: Builder container
FROM fedora:latest AS builder

# Install build dependencies
RUN dnf install -y pandoc && dnf clean all

# Copy source files to builder
WORKDIR /build
COPY . .

# Run the blog build script to generate static HTML files
RUN ./scripts/blog-build.sh

# Stage 2: Runtime container
FROM quay.io/fedora/httpd-24

# Copy only the generated files from the builder stage
COPY --from=builder --chown=1001:0 /build /var/www/html/

# Configure Apache httpd settings (abbreviated)
# ...
```

The build has two stages:

1. A builder stage that installs Pandoc and runs the build script
2. A runtime stage using a minimal Apache HTTPD image that serves the static files

This approach results in a tiny production container that's secure and fast to deploy.

### The Build Script

The blog-build.sh script handles the Markdown to HTML conversion:

```bash
# Extract metadata from markdown file
title=$(grep -m 1 "^title:" "$md_file" | sed 's/^title: *//')
date=$(grep -m 1 "^date:" "$md_file" | sed 's/^date: *//')
author=$(grep -m 1 "^author:" "$md_file" | sed 's/^author: *//')
description=$(grep -m 1 "^description:" "$md_file" | sed 's/^description: *//')
tags_line=$(grep -m 1 "^tags:" "$md_file" | sed 's/^tags: *//')

# Use pandoc to convert Markdown to HTML
pandoc -f markdown -t html --no-highlight "$md_file" > "$content_file"

# Process images with captions
cat "$final_content_file" | sed -E 's|<p><img src="([^"]+)" alt="([^"]+)" /></p>|<figure>\n  <img src="\1" alt="\2" class="w-full rounded-md shadow-lg" />\n  <figcaption>\2</figcaption>\n</figure>|g' > "$image_content_file"
```

The script extracts metadata from frontmatter, converts Markdown to HTML, and applies custom styling and formatting to elements like code blocks and images.

It also handles generating the blog index and RSS feed automatically:

```bash
# Update the blog index
for file in "${sorted_files[@]}"; do
    post_data="${posts[$file]}"
    IFS='|' read -r title date description tags_html_file <<< "$post_data"
    
    # Get tags HTML from file
    tags_html=$(cat "$tags_html_file")
    
    cat >> "$temp_index" << EOF
<div class="py-4 border-b border-gray-700 dark:border-gray-600">
  <p class="text-sm text-gray-500 mb-2">$date</p>
  <h2 class="text-xl mb-2">
    <a href="$file" class="text-purple-500 dark:text-purple-400 no-underline transition-colors duration-200 hover:text-black dark:hover:text-white hover:underline">$title</a>
  </h2>
  <p class="text-gray-300 mb-2">$description</p>
  <div class="flex flex-wrap">
    $tags_html
  </div>
</div>
EOF
done
```

Another benefit of this approach is that I can always update the blog post template and just re-render the pages.

### Pre-Commit Hooks Instead of CI Pipelines

Rather than setting up complex CI/CD pipelines, I've implemented pre-commit hooks that validate and format content before it's committed. These hooks:

- Check for broken links
- Validate Markdown syntax
- Ensure frontmatter is correctly formatted
- Run a spell checker to catch obvious typos
- Optimize images to keep page load times fast

This catches issues early and ensures the repository always contains publish-ready content. It's much simpler than waiting for a pipeline to fail after pushing changes.

### The Beauty of Static

The final output is a completely static site -- no database, no server-side processing, and no dynamic content generation. This approach has several advantages:

- Lightning-fast page loads
- Excellent security profile (no attack surface)
- Easy deployment (it's just files)
- Minimal hosting requirements
- Perfect caching behavior

Since everything is version-controlled, I have a complete history of changes and can easily roll back if needed. 

## Looking Forward

This setup gives me complete control while keeping things refreshingly simple. No fighting with CMS quirks, no database migrations, and no dependency hell -- just content and code, both handled elegantly.

Welcome to my blog -- I hope you'll find something valuable here.
