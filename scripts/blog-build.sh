#!/bin/bash
set -e

# Configuration
BLOG_DIR="blog"
TEMPLATE_FILE="$BLOG_DIR/template.html"
INDEX_FILE="$BLOG_DIR/index.html"
RSS_FILE="rss.xml"
SITEMAP_FILE="sitemap.xml"
SITE_URL="https://josie.lol"

# Configuration - Add talks directory
TALKS_DIR="talks"
TALKS_INDEX_FILE="$TALKS_DIR/index.html"

# Ensure required commands are available
if ! command -v pandoc &> /dev/null; then
    echo "Error: pandoc is not installed. Please install it with:"
    echo "  sudo pacman -S pandoc  # For Arch Linux"
    exit 1
fi

echo "Building blog posts from Markdown..."

# Create RSS feed header if it doesn't exist
if [ ! -f "$RSS_FILE" ]; then
    cat > "$RSS_FILE" << EOF
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
<channel>
  <title>josie.lol Blog</title>
  <link>${SITE_URL}</link>
  <description>Thoughts on cloud-native tech, infrastructure, security, and developer experience</description>
  <atom:link href="${SITE_URL}/${RSS_FILE}" rel="self" type="application/rss+xml" />
  <language>en-us</language>
  <lastBuildDate>$(date -R)</lastBuildDate>
  
<!-- POSTS_START -->
<!-- POSTS_END -->

</channel>
</rss>
EOF
    echo "Created new RSS feed file"
fi

# Initialize or read the posts array
declare -A posts
post_files=()

# Process each markdown file in the blog directory
for md_file in $(find "$BLOG_DIR" -name "*.md" | sort -r); do
    filename=$(basename "$md_file")
    html_filename="${filename%.md}.html"
    
    # Skip processing template and index files
    if [[ "$filename" == "template.md" || "$filename" == "index.md" ]]; then
        continue
    fi
    
    echo "Processing: $filename"
    
    # Extract metadata from markdown file
    title=$(grep -m 1 "^title:" "$md_file" | sed 's/^title: *//')
    date=$(grep -m 1 "^date:" "$md_file" | sed 's/^date: *//')
    author=$(grep -m 1 "^author:" "$md_file" | sed 's/^author: *//')
    description=$(grep -m 1 "^description:" "$md_file" | sed 's/^description: *//')
    tags_line=$(grep -m 1 "^tags:" "$md_file" | sed 's/^tags: *//')
    og_image=$(grep -m 1 "^og_image:" "$md_file" | sed 's/^og_image: *//')
    
    # Generate canonical URL for this blog post
    canonical_url="${SITE_URL}/blog/${html_filename}"
    
    # Set default og:image if not specified
    if [[ -z "$og_image" ]]; then
        # Use the terminal screenshot as default
        og_image="${SITE_URL}/screenshot.png"
    else
        # If og_image is a relative path, make it absolute
        if [[ ! "$og_image" =~ ^https?:// ]]; then
            og_image="${SITE_URL}${og_image}"
        fi
    fi
    
    # Extract guest post metadata
    guest_post=$(grep -m 1 "^guest_post:" "$md_file" | sed 's/^guest_post: *//')
    guest_bio=$(grep -m 1 "^guest_bio:" "$md_file" | sed 's/^guest_bio: *//')
    guest_link=$(grep -m 1 "^guest_link:" "$md_file" | sed 's/^guest_link: *//')
    
    # Extract external post metadata
    external_post=$(grep -m 1 "^external_post:" "$md_file" | sed 's/^external_post: *//')
    external_url=$(grep -m 1 "^external_url:" "$md_file" | sed 's/^external_url: *//')
    external_publication=$(grep -m 1 "^external_publication:" "$md_file" | sed 's/^external_publication: *//')
    
    # Format tags as comma-separated list for meta tags (for <meta> tags)
    tags_meta=$(echo "$tags_line" | sed 's/\[//g' | sed 's/\]//g')
    
    # Create an ISO date for meta tags
    date_iso="${date}T12:00:00Z"
    
    # Generate HTML tags for each tag and save to a file
    tags_html_file=$(mktemp)
    
    # Extract tags from the [tag1, tag2, ...] format
    if [[ "$tags_line" =~ \[(.*)\] ]]; then
        IFS=', ' read -r -a tag_array <<< "${BASH_REMATCH[1]}"
        for tag in "${tag_array[@]}"; do
            # Remove any quotes around the tag
            tag=$(echo "$tag" | sed 's/^"//g' | sed 's/"$//g' | sed "s/^'//g" | sed "s/'$//g")
            echo -n "<span class=\"text-xs mr-2 mb-2 px-2 py-1 bg-purple-900 bg-opacity-30 rounded-md\">$tag</span>" >> "$tags_html_file"
        done
    fi
    
    # For external posts, we only need metadata for the index, skip HTML generation
    if [[ "$external_post" == "true" ]]; then
        echo "External post detected, skipping HTML generation"
        # Store metadata for index generation
        posts["$html_filename"]="$title|$date|$description|$tags_html_file|$guest_post|$author|$external_post|$external_url|$external_publication"
        post_files+=("$html_filename")
        continue
    fi
    
    # Convert markdown to HTML using pandoc and save to a file
    content_file=$(mktemp)
    
    # Use pandoc with syntax highlighting enabled (remove --no-highlight flag)
    pandoc -f markdown -t html --highlight-style=pygments "$md_file" > "$content_file"
    
    # Process the generated HTML to adjust the HTML structure but preserve highlighting
    final_content_file=$(mktemp)
    
    # Fix code blocks - adjust data attributes while preserving Pandoc's highlighting
    # Use sed to handle the replacements while preserving newlines
    sed -E '
    # For div.sourceCode with pre tags on same line
    s|<div class="sourceCode" id="[^"]+"><pre class="sourceCode ([^"]+)">|<div class="sourceCode"><pre data-prompt="\1" class="sourceCode \1">|g
    
    # For div.sourceCode with pre tags on next line - join lines first
    /<div class="sourceCode"/ {
        N
        s|<div class="sourceCode" id="[^"]+">[\n[:space:]]*<pre[\n[:space:]]+class="sourceCode ([^"]+)">|<div class="sourceCode"><pre data-prompt="\1" class="sourceCode \1">|g
    }
    
    # For inline code blocks
    s|<pre><code class="sourceCode ([^"]+)">|<pre data-prompt="\1"><code class="sourceCode language-\1">|g
    
    # For code blocks without language
    s|<pre><code>|<pre data-prompt="bash"><code class="no-language">|g
    ' "$content_file" > "$final_content_file"
    
    # Process images with captions (standard Markdown images are converted to figures with captions)
    image_content_file=$(mktemp)
    
    # This regex matches the pattern for <p><img src="..." alt="..." /></p> and transforms it to figure with caption
    # It extracts the alt text as the caption and adds it to a figcaption element
    cat "$final_content_file" | sed -E 's|<p><img src="([^"]+)" alt="([^"]+)" /></p>|<figure>\n  <img src="\1" alt="\2" class="w-full rounded-md shadow-lg" />\n  <figcaption>\2</figcaption>\n</figure>|g' > "$image_content_file"
    
    # Replace the content file with the improved version
    mv "$image_content_file" "$final_content_file"
    mv "$final_content_file" "$content_file"
    
    # Copy template to a working file
    working_file=$(mktemp)
    cp "$TEMPLATE_FILE" "$working_file"
    
    # Replace simple placeholders - use | as delimiter to handle slashes in content
    sed -i "s|TITLE_PLACEHOLDER|$title|g" "$working_file"
    sed -i "s|DESCRIPTION_PLACEHOLDER|$description|g" "$working_file"
    sed -i "s|AUTHOR_PLACEHOLDER|$author|g" "$working_file"
    sed -i "s|DATE_PLACEHOLDER|$date|g" "$working_file"
    sed -i "s|DATE_ISO_PLACEHOLDER|$date_iso|g" "$working_file"
    sed -i "s|TAGS_PLACEHOLDER|$tags_meta|g" "$working_file"
    sed -i "s|URL_PLACEHOLDER|$html_filename|g" "$working_file"
    sed -i "s|CANONICAL_URL_PLACEHOLDER|$canonical_url|g" "$working_file"
    sed -i "s|CANONICAL_$html_filename|$canonical_url|g" "$working_file"
    sed -i "s|OG_IMAGE_PLACEHOLDER|$og_image|g" "$working_file"
    
    # Read the tags HTML and content files
    tags_html=$(cat "$tags_html_file")
    
    # Create a temp file for the final HTML
    final_html=$(mktemp)
    
    # Generate guest post badge and bio HTML
    guest_badge_html=""
    guest_bio_html=""
    
    if [[ "$guest_post" == "true" ]]; then
        guest_badge_html='<span class="guest-post-badge">guest post</span>'
        
        if [[ ! -z "$guest_bio" ]]; then
            # Escape special characters in guest bio
            escaped_bio=$(printf '%s' "$guest_bio" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
            guest_bio_html="<div class=\"guest-author-bio\"><h3>about the guest author</h3><p>$escaped_bio</p>"
            if [[ ! -z "$guest_link" ]]; then
                guest_bio_html+="<p><a href=\"$guest_link\" target=\"_blank\" rel=\"noopener noreferrer\">learn more about $author →</a></p>"
            fi
            guest_bio_html+="</div>"
        fi
    fi
    
    # Process the working file line by line until we find CONTENT_PLACEHOLDER
    content_found=false
    while IFS= read -r line; do
        if [[ "$line" == *"TAGS_HTML_PLACEHOLDER"* ]]; then
            # This line contains the tags placeholder, replace it
            echo "${line/TAGS_HTML_PLACEHOLDER/$tags_html}" >> "$final_html"
        elif [[ "$line" == *"GUEST_BADGE_PLACEHOLDER"* ]]; then
            # Replace guest badge placeholder
            echo "${line/GUEST_BADGE_PLACEHOLDER/$guest_badge_html}" >> "$final_html"
        elif [[ "$line" == *"GUEST_BIO_PLACEHOLDER"* ]]; then
            # Replace guest bio placeholder
            echo "${line/GUEST_BIO_PLACEHOLDER/$guest_bio_html}" >> "$final_html"
        elif [[ "$line" == *"CONTENT_PLACEHOLDER"* && "$content_found" == false ]]; then
            # Found the content placeholder
            content_found=true
            
            # Insert the entire content from the file
            cat "$content_file" >> "$final_html"
        else
            # Skip lines with CONTENT_PLACEHOLDER if we've already processed it
            if [[ "$line" != *"CONTENT_PLACEHOLDER"* ]]; then
                # Regular line, just copy it (but replace any remaining CANONICAL_URL_PLACEHOLDER)
                echo "${line//CANONICAL_URL_PLACEHOLDER/$canonical_url}" >> "$final_html"
            fi
        fi
    done < "$working_file"
    
    # Copy the final HTML to the target location
    cp "$final_html" "$BLOG_DIR/$html_filename"
    
    # Clean up temp files
    rm "$tags_html_file" "$content_file" "$working_file" "$final_html"
    
    echo "Generated: $BLOG_DIR/$html_filename"
    
    # Store paths and metadata for index and RSS
    # Store HTML tags for each tag (can't store directly in associative array due to special chars)
    tags_html_file=$(mktemp)
    cat > "$tags_html_file" << EOF
$(cat "$BLOG_DIR/$html_filename" | grep -o '<span class="text-xs mr-2 mb-2.*rounded-md">.*</span>' || echo "")
EOF
    
    posts["$html_filename"]="$title|$date|$description|$tags_html_file|$guest_post|$author|$external_post|$external_url|$external_publication"
    post_files+=("$html_filename")
done

# Sort post files by date (assuming YYYY-MM-DD format in filename or metadata)
# shellcheck disable=SC2207
IFS=$'\n' sorted_files=($(
    for file in "${post_files[@]}"; do
        date=$(echo "${posts[$file]}" | cut -d'|' -f2)
        echo "$date|$file"
    done | sort -r | cut -d'|' -f2
))
unset IFS

# Update blog index.html with post list
if [ -f "$INDEX_FILE" ]; then
    echo "Updating blog index..."
    
    # Create a temp file for the rebuilt index
    temp_index=$(mktemp)
    
    # Variables to track if we're in the post list section
    in_post_list=false
    
    # Read the index file line by line
    while IFS= read -r line; do
        if [[ "$line" == *"<!-- BLOG_POST_LIST_START -->"* ]]; then
            echo "$line" >> "$temp_index"
            in_post_list=true
            
            # Add all posts
            for file in "${sorted_files[@]}"; do
                post_data="${posts[$file]}"
                IFS='|' read -r title date description tags_html_file is_guest author_name is_external external_url external_publication <<< "$post_data"
                
                # Get tags HTML from file
                tags_html=$(cat "$tags_html_file")
                
                # Generate badges for index
                badges=""
                author_text="$author_name"
                if [[ "$is_guest" == "true" ]]; then
                    badges+=' <span class="guest-post-badge">guest post</span>'
                fi
                if [[ "$is_external" == "true" ]]; then
                    badges+=" · <span class=\"external-post-badge\">Published on $external_publication</span>"
                fi
                
                # Set the correct URL
                post_url="$file"
                if [[ "$is_external" == "true" ]]; then
                    post_url="$external_url"
                fi
                
                cat >> "$temp_index" << EOF
        <div class="py-4 border-b border-gray-700 dark:border-gray-600">
          <p class="text-sm text-gray-500 mb-2">$date · by $author_text$badges</p>
          <h2 class="text-xl mb-2">
            <a href="$post_url" class="text-purple-500 dark:text-purple-400 no-underline transition-colors duration-200 hover:text-black dark:hover:text-white hover:underline"$(if [[ "$is_external" == "true" ]]; then echo ' target="_blank" rel="noopener noreferrer"'; fi)>$title$(if [[ "$is_external" == "true" ]]; then echo ' ↗'; fi)</a>
          </h2>
          <p class="text-gray-300 mb-2">$description</p>
          <div class="flex flex-wrap">
            $tags_html
          </div>
        </div>
EOF
            done
        elif [[ "$line" == *"<!-- BLOG_POST_LIST_END -->"* ]]; then
            echo "$line" >> "$temp_index"
            in_post_list=false
        elif [[ "$in_post_list" == false ]]; then
            echo "$line" >> "$temp_index"
        fi
    done < "$INDEX_FILE"
    
    # Replace the original index file
    cp "$temp_index" "$INDEX_FILE"
    rm "$temp_index"
    
    echo "Updated blog index page"
fi

# Update RSS feed with posts
if [ -f "$RSS_FILE" ]; then
    echo "Updating RSS feed..."
    
    # Create a temp file for the rebuilt RSS
    temp_rss=$(mktemp)
    
    # Variables to track if we're in the posts section
    in_posts=false
    
    # Read the RSS file line by line
    while IFS= read -r line; do
        if [[ "$line" == *"<!-- POSTS_START -->"* ]]; then
            echo "$line" >> "$temp_rss"
            in_posts=true
            
            # Add all posts
            for file in "${sorted_files[@]}"; do
                post_data="${posts[$file]}"
                IFS='|' read -r title date description tags_html_file is_guest author_name is_external external_url external_publication <<< "$post_data"
                
                # Convert date to RFC822 format for RSS; tolerate YYYY-MM by appending -01
                rfc_date=$(date -d "$date" -R 2>/dev/null || date -d "${date}-01" -R 2>/dev/null || echo "")
                
                # Set the correct URL
                post_link="${SITE_URL}/blog/$file"
                if [[ "$is_external" == "true" ]]; then
                    post_link="$external_url"
                fi
                
                # Add external publication to title if external
                display_title="$title"
                if [[ "$is_external" == "true" ]]; then
                    display_title="$title (via $external_publication)"
                fi
                
                cat >> "$temp_rss" << EOF
  <item>
    <title>$display_title</title>
    <link>$post_link</link>
    <description><![CDATA[$description]]></description>
    <pubDate>$rfc_date</pubDate>
    <guid>$post_link</guid>
  </item>
EOF
            done
        elif [[ "$line" == *"<!-- POSTS_END -->"* ]]; then
            echo "$line" >> "$temp_rss"
            in_posts=false
        elif [[ "$line" == *"<lastBuildDate>"* ]]; then
            # Derive lastBuildDate from the most recent post so rebuilds are idempotent
            build_date=""
            if [[ ${#sorted_files[@]} -gt 0 ]]; then
                latest_post_data="${posts[${sorted_files[0]}]}"
                IFS='|' read -r _ latest_date _ <<< "$latest_post_data"
                build_date=$(date -d "$latest_date" -R 2>/dev/null)
            fi
            [[ -z "$build_date" ]] && build_date=$(date -R)
            echo "  <lastBuildDate>$build_date</lastBuildDate>" >> "$temp_rss"
        elif [[ "$in_posts" == false ]]; then
            echo "$line" >> "$temp_rss"
        fi
    done < "$RSS_FILE"
    
    # Replace the original RSS file
    cp "$temp_rss" "$RSS_FILE"
    rm "$temp_rss"
    
    echo "Updated RSS feed"
fi

# Clean up any remaining temp files
for file in "${post_files[@]}"; do
    post_data="${posts[$file]}"
    IFS='|' read -r title date description tags_html_file <<< "$post_data"
    
    # Remove temp tag file if it exists
    if [[ -f "$tags_html_file" ]]; then
        rm "$tags_html_file"
    fi
done

echo "Blog build completed successfully!"

# After processing blog posts, process talks
echo "Building talks index..."

# Check if the index file exists and has the right markers
if ! grep -q "<!-- TALKS_LIST_START -->" "$TALKS_INDEX_FILE"; then
    echo "Could not find TALKS_LIST_START marker in $TALKS_INDEX_FILE"
    exit 1
fi

if ! grep -q "<!-- TALKS_LIST_END -->" "$TALKS_INDEX_FILE"; then
    echo "Could not find TALKS_LIST_END marker in $TALKS_INDEX_FILE"
    exit 1
fi

# Create a temp file for the rebuilt index
temp_index=$(mktemp)

# Copy everything before the TALKS_LIST_START marker
sed -n '1,/<!-- TALKS_LIST_START -->/p' "$TALKS_INDEX_FILE" > "$temp_index"

# Find markdown files
talk_files=$(find "$TALKS_DIR" -name "*.md" | grep -v "index.md" | grep -v "template.md")
talk_count=$(echo "$talk_files" | wc -l)
echo "Found $talk_count talk markdown files"

# Array to store talk data for sorting
declare -a talk_data_array=()

# First pass: collect all talk data
for md_file in $talk_files; do
    filename=$(basename "$md_file")
    echo "Processing talk: $filename"
    
    # Extract basic metadata with debug output
    title=$(grep -m 1 "^title:" "$md_file" | sed 's/^title: *//')
    echo "  Title: $title"
    
    date=$(grep -m 1 "^date:" "$md_file" | sed 's/^date: *//')
    echo "  Date: $date"
    
    abstract=$(grep -m 1 "^abstract:" "$md_file" | sed 's/^abstract: *//')
    echo "  Abstract: $abstract"
    
    # Extract related blog post
    related_post=$(grep -m 1 "^related_post:" "$md_file" | sed 's/^related_post: *//')
    if [[ ! -z "$related_post" ]]; then
        echo "  Related post: $related_post"
    fi
    
    # Note: slides and recording are now per-conference, handled below
    
    # Debug: show the conferences section
    echo "  Extracting conferences section:"
    sed -n '/^conferences:/,/^---/p' "$md_file"
    
    # Manually extract conferences with per-conference slides/recordings
    conferences_html=""
    # Array to collect conference data for sorting
    declare -a conference_data=()
    
    # Find the line number of 'conferences:' in the file
    conf_line=$(grep -n "^conferences:" "$md_file" | cut -d: -f1)
    
    if [[ ! -z "$conf_line" ]]; then
        echo "  Found conferences section at line $conf_line"
        
        # Read the file line by line starting from the conferences line
        in_conferences=false
        conf_name=""
        conf_location=""
        conf_date=""
        conf_slides=""
        conf_recording=""
        conf_cancelled=""
        
        while IFS= read -r line; do
            if [[ "$line" == "conferences:" ]]; then
                in_conferences=true
                continue
            fi
            
            if [[ "$in_conferences" == true ]]; then
                if [[ "$line" == "---" || "$line" == "" ]]; then
                    # End of frontmatter or empty line
                    break
                fi
                
                if [[ "$line" =~ ^[[:space:]]+- ]]; then
                    # Before starting a new conference, save the previous one if it exists
                    if [[ ! -z "$conf_name" && ! -z "$conf_date" ]]; then
                        # Save conference data to temp file for sorting
                        conf_temp_file=$(mktemp)
                        echo "$conf_date|$conf_name|$conf_location|$conf_slides|$conf_recording|$conf_cancelled" > "$conf_temp_file"
                        conference_data+=("$conf_temp_file")
                        echo "    Added conference data: $conf_name"
                    fi
                    
                    # Start of a new conference entry
                    echo "    New conference entry: $line"
                    # Reset variables for new conference
                    conf_name=""
                    conf_location=""
                    conf_date=""
                    conf_slides=""
                    conf_recording=""
                    conf_cancelled=""
                fi
                
                if [[ "$line" =~ name: ]]; then
                    conf_name=$(echo "$line" | sed 's/.*name:[[:space:]]*//')
                    echo "    Name: $conf_name"
                fi
                
                if [[ "$line" =~ location: ]]; then
                    conf_location=$(echo "$line" | sed 's/.*location:[[:space:]]*//')
                    echo "    Location: $conf_location"
                fi
                
                if [[ "$line" =~ slides: ]]; then
                    conf_slides=$(echo "$line" | sed 's/.*slides:[[:space:]]*//')
                    # Fix slides path if needed
                    if [[ "$conf_slides" == "/slides/"* ]]; then
                        conf_slides="/talks${conf_slides}"
                    fi
                    echo "    Slides: $conf_slides"
                fi
                
                if [[ "$line" =~ recording: ]]; then
                    conf_recording=$(echo "$line" | sed 's/.*recording:[[:space:]]*//')
                    echo "    Recording: $conf_recording"
                fi
                
                if [[ "$line" =~ cancelled: ]]; then
                    conf_cancelled=$(echo "$line" | sed 's/.*cancelled:[[:space:]]*//')
                    echo "    Cancelled: $conf_cancelled"
                fi
                
                if [[ "$line" =~ date: && ! "$line" =~ "date: 20" ]]; then
                    # Skip if this is the conference date field (which contains year)
                    continue
                fi
                
                if [[ "$line" =~ date: && "$line" =~ "date: 20" ]]; then
                    conf_date=$(echo "$line" | sed 's/.*date:[[:space:]]*//')
                    echo "    Date: $conf_date"
                fi
            fi
        done < "$md_file"
        
        # Save the last conference if it exists
        if [[ ! -z "$conf_name" && ! -z "$conf_date" ]]; then
            conf_temp_file=$(mktemp)
            echo "$conf_date|$conf_name|$conf_location|$conf_slides|$conf_recording|$conf_cancelled" > "$conf_temp_file"
            conference_data+=("$conf_temp_file")
            echo "    Added conference data: $conf_name"
        fi
        
        # Sort conferences by date and build HTML
        if [ ${#conference_data[@]} -gt 0 ]; then
            # Sort conference files by date (first field)
            sorted_conferences=$(for file in "${conference_data[@]}"; do
                echo "$(head -n1 "$file" | cut -d'|' -f1)|$file"
            done | sort -r | cut -d'|' -f2)
            
            # Build HTML for each conference in sorted order
            for conf_file in $sorted_conferences; do
                IFS='|' read -r conf_date conf_name conf_location conf_slides conf_recording conf_cancelled < "$conf_file"
                
                conf_entry="<div class=\"mb-3\">"
                
                # Check if conference is upcoming (in the future)
                current_date=$(date +%Y-%m-%d)
                is_upcoming=false
                if [[ "$conf_date" > "$current_date" ]]; then
                    is_upcoming=true
                fi
                
                # Apply strikethrough if cancelled
                if [[ "$conf_cancelled" == "true" ]]; then
                    conf_entry+="<div class=\"font-semibold line-through opacity-50\">$conf_name</div>"
                    conf_entry+="<div class=\"text-sm text-gray-500 line-through opacity-50\">$conf_location ($conf_date)</div>"
                    conf_entry+="<div class=\"text-sm text-gray-500 italic\">cancelled</div>"
                else
                    conf_entry+="<div class=\"font-semibold\">$conf_name</div>"
                    conf_entry+="<div class=\"text-sm text-gray-500\">$conf_location ($conf_date)</div>"
                    
                    # Add upcoming badge if conference is in the future
                    if [[ "$is_upcoming" == "true" ]]; then
                        conf_entry+="<div class=\"text-sm\"><span class=\"inline-block px-2 py-1 bg-green-900 bg-opacity-30 text-green-400 rounded text-xs font-semibold\">upcoming</span></div>"
                    fi
                fi
                
                # Add links for this conference (only if not cancelled)
                if [[ "$conf_cancelled" != "true" && (! -z "$conf_slides" || ! -z "$conf_recording") ]]; then
                    conf_entry+="<div class=\"mt-1\">"
                    if [[ ! -z "$conf_slides" ]]; then
                        conf_entry+="<a href=\"$conf_slides\" class=\"text-purple-500 dark:text-purple-400 mr-3 text-sm no-underline transition-colors duration-200 hover:text-white hover:underline\">slides</a>"
                    fi
                    if [[ ! -z "$conf_recording" ]]; then
                        conf_entry+="<a href=\"$conf_recording\" class=\"text-purple-500 dark:text-purple-400 text-sm no-underline transition-colors duration-200 hover:text-white hover:underline\">recording</a>"
                    fi
                    conf_entry+="</div>"
                fi
                
                conf_entry+="</div>"
                conferences_html+="$conf_entry"
                
                # Clean up temp file
                rm "$conf_file"
            done
        fi
    else
        echo "  No conferences section found"
    fi
    
    echo "  Conferences HTML: $conferences_html"
    
    # Store talk data for sorting
    # Create a temporary file to store this talk's data
    talk_temp_file=$(mktemp)
    cat > "$talk_temp_file" << EOF
$date|$title|$abstract|$related_post|$conferences_html
EOF
    talk_data_array+=("$talk_temp_file")
    
    echo "Collected $title"
done

# Sort talks by date in descending order and write to index
echo "        <!-- Auto-generated talks list -->" >> "$temp_index"

# Sort the talk data files by date (first field) in reverse order
sorted_talks=$(for file in "${talk_data_array[@]}"; do
    echo "$(head -n1 "$file" | cut -d'|' -f1)|$file"
done | sort -r | cut -d'|' -f2)

# Now write the sorted talks to the index
for talk_file in $sorted_talks; do
    # Read the talk data
    IFS='|' read -r date title abstract related_post conferences_html < "$talk_file"
    
    # Write the talk entry to the index file
    cat >> "$temp_index" << EOF
        <div class="py-6 border-b border-gray-700 dark:border-gray-600">
          <h2 class="text-xl font-bold mb-2 text-purple-400">$title</h2>
          <p class="text-gray-300 mb-4">$abstract</p>
EOF
    
    # Add related blog post link if available
    if [[ ! -z "$related_post" ]]; then
        cat >> "$temp_index" << EOF
          <p class="mb-4"><a href="$related_post" class="text-purple-500 dark:text-purple-400 no-underline transition-colors duration-200 hover:text-white hover:underline">Read related blog post →</a></p>
EOF
    fi
    
    cat >> "$temp_index" << EOF
          <div class="text-base text-gray-400">
            <p class="mb-2 font-bold">presented at:</p>
            $conferences_html
          </div>
        </div>
EOF
    
    # Clean up temp file
    rm "$talk_file"
done

# Copy everything after the TALKS_LIST_END marker
sed -n '/<!-- TALKS_LIST_END -->/,$p' "$TALKS_INDEX_FILE" >> "$temp_index"

# Replace the original index file
cp "$temp_index" "$TALKS_INDEX_FILE"
rm "$temp_index"

echo "Updated talks index page at $TALKS_INDEX_FILE"

# After processing blog posts and talks, generate sitemap
echo "Generating sitemap..."

# Create a temp file for the sitemap
temp_sitemap=$(mktemp)

# Add XML header and urlset opening tag
cat > "$temp_sitemap" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <!-- Main pages -->
  <url>
    <loc>${SITE_URL}/</loc>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>${SITE_URL}/blog/</loc>
    <changefreq>weekly</changefreq>
    <priority>0.9</priority>
  </url>
  <url>
    <loc>${SITE_URL}/talks/</loc>
    <changefreq>monthly</changefreq>
    <priority>0.9</priority>
  </url>
EOF

# Add blog posts to sitemap
for file in "${sorted_files[@]}"; do
    post_data="${posts[$file]}"
    IFS='|' read -r title date description tags_html_file <<< "$post_data"
    
    # Convert date to W3C format (YYYY-MM-DD) for sitemap
    w3c_date=$(date -d "$date" +%Y-%m-%d 2>/dev/null || echo "$date")
    
    cat >> "$temp_sitemap" << EOF
  <url>
    <loc>${SITE_URL}/blog/$file</loc>
    <lastmod>${w3c_date}</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.8</priority>
  </url>
EOF
done

# Add talks to sitemap if there are any
if [ -n "$talk_files" ]; then
    for md_file in $talk_files; do
        filename=$(basename "$md_file")
        date=$(grep -m 1 "^date:" "$md_file" | sed 's/^date: *//')
        # Convert date to W3C format for sitemap
        w3c_date=$(date -d "$date" +%Y-%m-%d 2>/dev/null || echo "$date")
        
        # Extract all slides paths from conferences for sitemap
        # Find all lines with "slides:" in the conferences section
        slides_lines=$(sed -n '/^conferences:/,/^---/{/slides:/p}' "$md_file")
        
        if [[ ! -z "$slides_lines" ]]; then
            while IFS= read -r slide_line; do
                slides=$(echo "$slide_line" | sed 's/.*slides:[[:space:]]*//')
                if [[ ! -z "$slides" ]]; then
                    # Fix slides path if needed
                    if [[ "$slides" == "/slides/"* ]]; then
                        slides="/talks${slides}"
                    fi
                    
                    cat >> "$temp_sitemap" << EOF
  <url>
    <loc>${SITE_URL}${slides}</loc>
    <lastmod>${w3c_date}</lastmod>
    <changefreq>yearly</changefreq>
    <priority>0.7</priority>
  </url>
EOF
                fi
            done <<< "$slides_lines"
        fi
    done
fi

# Close the urlset tag
echo "</urlset>" >> "$temp_sitemap"

# Replace the original sitemap file
cp "$temp_sitemap" "$SITEMAP_FILE"
rm "$temp_sitemap"

echo "Generated sitemap at $SITEMAP_FILE"

# === Books / Papers JSON-LD on index.html ===

PERSON_ID="${SITE_URL}/#person"
BOOKS_DIR="data/books"
PAPERS_DIR="data/papers"
TESTIMONIALS_DIR="data/testimonials"
AWARDS_DIR="data/awards"

# Extract the body of a markdown file (everything after the second '---').
md_body() {
    awk 'BEGIN{n=0} /^---$/{n++; next} n>=2 {print}' "$1"
}

# Extract the first paragraph of a markdown body (collapses lines until blank).
first_paragraph() {
    awk '
        /^$/ && p != "" { print p; p = ""; exit }
        { if (p == "") p = $0; else p = p " " $0 }
        END { if (p != "") print p }
    '
}

if ! command -v jq &> /dev/null; then
    echo "jq not found, skipping JSON-LD enrichment + llms.txt generation"
else
    echo "Generating books/papers JSON-LD..."

    books_arr=$(mktemp); echo "[]" > "$books_arr"
    papers_arr=$(mktemp); echo "[]" > "$papers_arr"

    book_idx=0
    if [[ -d "$BOOKS_DIR" ]]; then
        for md in $(find "$BOOKS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
            b_title=$(grep -m 1 "^title:" "$md" | sed 's/^title: *//')
            b_isbn=$(grep -m 1 "^isbn:" "$md" | sed 's/^isbn: *//')
            b_pub=$(grep -m 1 "^datePublished:" "$md" | sed 's/^datePublished: *//')
            b_publisher=$(grep -m 1 "^publisher:" "$md" | sed 's/^publisher: *//')
            b_url=$(grep -m 1 "^url:" "$md" | sed 's/^url: *//')
            b_desc=$(md_body "$md" | first_paragraph)

            jq --arg id "${SITE_URL}/#book-${book_idx}" \
               --arg name "$b_title" \
               --arg isbn "$b_isbn" \
               --arg pub "$b_pub" \
               --arg publisher "$b_publisher" \
               --arg url "$b_url" \
               --arg desc "$b_desc" \
               --arg pid "$PERSON_ID" \
               '. += [({
                   "@type": "Book",
                   "@id": $id,
                   "name": $name,
                   "author": {"@id": $pid},
                   "isbn": $isbn,
                   "datePublished": $pub,
                   "publisher": $publisher,
                   "url": $url,
                   "description": $desc
               } | with_entries(select(.value != null and .value != "" and .value != {})))]' \
               "$books_arr" > "$books_arr.tmp" && mv "$books_arr.tmp" "$books_arr"

            book_idx=$((book_idx + 1))
        done
    fi

    paper_idx=0
    if [[ -d "$PAPERS_DIR" ]]; then
        for md in $(find "$PAPERS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
            p_title=$(grep -m 1 "^title:" "$md" | sed 's/^title: *//')
            p_authors_line=$(grep -m 1 "^authors:" "$md" | sed 's/^authors: *//')
            p_pub=$(grep -m 1 "^datePublished:" "$md" | sed 's/^datePublished: *//')
            p_venue=$(grep -m 1 "^venue:" "$md" | sed 's/^venue: *//')
            p_url=$(grep -m 1 "^url:" "$md" | sed 's/^url: *//')
            p_doi=$(grep -m 1 "^doi:" "$md" | sed 's/^doi: *//')
            p_abstract=$(md_body "$md" | first_paragraph)

            authors_json="[{\"@id\": \"$PERSON_ID\"}]"
            if [[ "$p_authors_line" =~ \[(.*)\] ]]; then
                IFS=',' read -r -a author_array <<< "${BASH_REMATCH[1]}"
                authors_json=$(
                    for a in "${author_array[@]}"; do
                        a=$(echo "$a" | sed -E 's/^[[:space:]]*"?'"'"'?//;s/"?'"'"'?[[:space:]]*$//')
                        printf '%s\n' "$a"
                    done | jq -R . | jq -s 'map({"@type": "Person", "name": .})'
                )
            fi

            jq --arg id "${SITE_URL}/#paper-${paper_idx}" \
               --arg name "$p_title" \
               --argjson authors "$authors_json" \
               --arg pub "$p_pub" \
               --arg venue "$p_venue" \
               --arg url "$p_url" \
               --arg doi "$p_doi" \
               --arg abstract "$p_abstract" \
               '. += [({
                   "@type": "ScholarlyArticle",
                   "@id": $id,
                   "headline": $name,
                   "author": $authors,
                   "datePublished": $pub,
                   "publisher": $venue,
                   "url": $url,
                   "identifier": (if $doi != "" then {"@type":"PropertyValue","propertyID":"DOI","value":$doi} else null end),
                   "abstract": $abstract
               } | with_entries(select(.value != null and .value != "" and .value != [])))]' \
               "$papers_arr" > "$papers_arr.tmp" && mv "$papers_arr.tmp" "$papers_arr"

            paper_idx=$((paper_idx + 1))
        done
    fi

    reviews_arr=$(mktemp); echo "[]" > "$reviews_arr"
    review_idx=0
    if [[ -d "$TESTIMONIALS_DIR" ]]; then
        for md in $(find "$TESTIMONIALS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
            r_author=$(grep -m 1 "^author:" "$md" | sed 's/^author: *//')
            r_title=$(grep -m 1 "^title:" "$md" | sed 's/^title: *//')
            r_url=$(grep -m 1 "^url:" "$md" | sed 's/^url: *//')
            r_date=$(grep -m 1 "^date:" "$md" | sed 's/^date: *//')
            r_body=$(md_body "$md" | awk 'NF{p=p?p" "$0:$0} END{if (p) print p}')
            r_slug=$(basename "${md%.md}")

            jq --arg id "${SITE_URL}/#review-${r_slug}" \
               --arg author "$r_author" \
               --arg title "$r_title" \
               --arg url "$r_url" \
               --arg date "$r_date" \
               --arg body "$r_body" \
               --arg pid "$PERSON_ID" \
               '. += [({
                   "@type": "Review",
                   "@id": $id,
                   "itemReviewed": {"@id": $pid},
                   "author": ({
                       "@type": "Person",
                       "name": $author,
                       "jobTitle": $title,
                       "url": $url
                   } | with_entries(select(.value != null and .value != ""))),
                   "datePublished": $date,
                   "reviewBody": $body
               } | with_entries(select(.value != null and .value != "" and .value != {})))]' \
               "$reviews_arr" > "$reviews_arr.tmp" && mv "$reviews_arr.tmp" "$reviews_arr"

            review_idx=$((review_idx + 1))
        done
    fi

    awards_arr=$(mktemp); echo "[]" > "$awards_arr"
    if [[ -d "$AWARDS_DIR" ]]; then
        for md in $(find "$AWARDS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
            a_name=$(grep -m 1 "^name:" "$md" | sed 's/^name: *//')
            a_awarder=$(grep -m 1 "^awarder:" "$md" | sed 's/^awarder: *//')
            a_date=$(grep -m 1 "^date:" "$md" | sed 's/^date: *//')
            a_year="${a_date%%-*}"

            display="$a_name"
            if [[ -n "$a_year" && -n "$a_awarder" ]]; then
                display="${a_name} (${a_year}, ${a_awarder})"
            elif [[ -n "$a_year" ]]; then
                display="${a_name} (${a_year})"
            elif [[ -n "$a_awarder" ]]; then
                display="${a_name} (${a_awarder})"
            fi

            jq --arg s "$display" '. += [$s]' "$awards_arr" > "$awards_arr.tmp" && mv "$awards_arr.tmp" "$awards_arr"
        done
    fi

    books_count=$(jq 'length' "$books_arr")
    papers_count=$(jq 'length' "$papers_arr")
    reviews_count=$(jq 'length' "$reviews_arr")
    awards_count=$(jq 'length' "$awards_arr")

    person_aug=$(mktemp); echo "[]" > "$person_aug"
    if [[ "$awards_count" -gt 0 ]]; then
        jq --arg pid "$PERSON_ID" --slurpfile awards "$awards_arr" \
            '. += [{"@type":"Person","@id":$pid,"award":$awards[0]}]' \
            "$person_aug" > "$person_aug.tmp" && mv "$person_aug.tmp" "$person_aug"
    fi

    bp_block=""
    if [[ "$books_count" -gt 0 || "$papers_count" -gt 0 || "$reviews_count" -gt 0 || "$awards_count" -gt 0 ]]; then
        bp_json=$(jq -n \
            --slurpfile books "$books_arr" \
            --slurpfile papers "$papers_arr" \
            --slurpfile reviews "$reviews_arr" \
            --slurpfile aug "$person_aug" \
            '{
                "@context": "https://schema.org",
                "@graph": ($books[0] + $papers[0] + $reviews[0] + $aug[0])
            }')
        bp_block=$(printf '    <script type="application/ld+json">\n%s\n    </script>' "$bp_json")
    fi
    rm "$books_arr" "$papers_arr" "$reviews_arr" "$awards_arr" "$person_aug"

    bp_block_file=$(mktemp)
    printf '%s\n' "$bp_block" > "$bp_block_file"

    awk -v bf="$bp_block_file" '
        /<!-- BOOKS_PAPERS_JSONLD_START -->/ {
            print
            while ((getline line < bf) > 0) print line
            close(bf)
            skip = 1
            next
        }
        /<!-- BOOKS_PAPERS_JSONLD_END -->/ {
            skip = 0
            print
            next
        }
        !skip { print }
    ' index.html > index.html.new && mv index.html.new index.html
    rm "$bp_block_file"
    echo "Updated books/papers JSON-LD on index.html"

    # === Talks JSON-LD on talks/index.html ===

    echo "Generating talks JSON-LD..."

    events_json=$(mktemp); echo "[]" > "$events_json"
    works_json=$(mktemp); echo "[]" > "$works_json"
    videos_json=$(mktemp); echo "[]" > "$videos_json"

    for md_file in $(find "$TALKS_DIR" -name "*.md" | grep -v "index.md" | grep -v "template.md"); do
        t_title=$(grep -m 1 "^title:" "$md_file" | sed 's/^title: *//')
        t_abstract=$(grep -m 1 "^abstract:" "$md_file" | sed 's/^abstract: *//')
        t_slug=$(basename "${md_file%.md}")
        t_id="${SITE_URL}/talks/#talk-${t_slug}"

        jq --arg id "$t_id" --arg name "$t_title" --arg desc "$t_abstract" --arg author "$PERSON_ID" \
            '. += [{
                "@type": "PresentationDigitalDocument",
                "@id": $id,
                "name": $name,
                "description": $desc,
                "author": {"@id": $author}
            }]' "$works_json" > "$works_json.tmp" && mv "$works_json.tmp" "$works_json"

        in_confs=false
        cn="" cl="" cd="" cs="" cr="" cc=""
        conf_idx=0

        flush_event() {
            local event_id="${SITE_URL}/talks/#event-${t_slug}-${conf_idx}"
            local slides_url=""
            if [[ -n "$cs" ]]; then
                if [[ "$cs" == /* ]]; then slides_url="${SITE_URL}${cs}"; else slides_url="$cs"; fi
            fi

            jq --arg id "$event_id" \
               --arg name "$cn" \
               --arg loc "$cl" \
               --arg date "$cd" \
               --arg slides "$slides_url" \
               --arg recording "$cr" \
               --arg cancelled "$cc" \
               --arg talk_id "$t_id" \
               --arg person_id "$PERSON_ID" \
               '. += [(
                   {
                       "@type": "Event",
                       "@id": $id,
                       "name": $name,
                       "startDate": $date,
                       "location": (if $loc != "" then {"@type":"Place","name":$loc} else null end),
                       "performer": {"@id": $person_id},
                       "workPresented": {"@id": $talk_id},
                       "eventStatus": (if $cancelled == "true" then "https://schema.org/EventCancelled" else null end)
                   } | with_entries(select(.value != null))
               )]' "$events_json" > "$events_json.tmp" && mv "$events_json.tmp" "$events_json"

            if [[ -n "$cr" ]]; then
                local video_id="${SITE_URL}/talks/#video-${t_slug}-${conf_idx}"
                local rec_clean="${cr%"${cr##*[![:space:]]}"}"
                jq --arg id "$video_id" \
                   --arg url "$rec_clean" \
                   --arg name "$cn" \
                   --arg desc "$t_abstract" \
                   --arg date "$cd" \
                   --arg author "$PERSON_ID" \
                   '. += [{
                       "@type": "VideoObject",
                       "@id": $id,
                       "contentUrl": $url,
                       "embedUrl": $url,
                       "name": $name,
                       "description": $desc,
                       "uploadDate": $date,
                       "author": {"@id": $author}
                   }]' "$videos_json" > "$videos_json.tmp" && mv "$videos_json.tmp" "$videos_json"
            fi
        }

        while IFS= read -r line; do
            if [[ "$line" == "conferences:" ]]; then in_confs=true; continue; fi
            if [[ "$in_confs" == false ]]; then continue; fi
            if [[ "$line" == "---" || "$line" == "" ]]; then break; fi

            if [[ "$line" =~ ^[[:space:]]+- ]]; then
                if [[ -n "$cn" && -n "$cd" ]]; then
                    flush_event
                    conf_idx=$((conf_idx + 1))
                fi
                cn=""; cl=""; cd=""; cs=""; cr=""; cc=""
            fi

            [[ "$line" =~ name: ]]      && cn=$(echo "$line" | sed 's/.*name:[[:space:]]*//')
            [[ "$line" =~ location: ]]  && cl=$(echo "$line" | sed 's/.*location:[[:space:]]*//')
            [[ "$line" =~ slides: ]]    && cs=$(echo "$line" | sed 's/.*slides:[[:space:]]*//')
            [[ "$line" =~ recording: ]] && cr=$(echo "$line" | sed 's/.*recording:[[:space:]]*//')
            [[ "$line" =~ cancelled: ]] && cc=$(echo "$line" | sed 's/.*cancelled:[[:space:]]*//')
            if [[ "$line" =~ date:[[:space:]]+20 ]]; then
                cd=$(echo "$line" | sed 's/.*date:[[:space:]]*//')
            fi
        done < "$md_file"

        if [[ -n "$cn" && -n "$cd" ]]; then
            flush_event
        fi
    done

    talks_jsonld=$(jq -n \
        --slurpfile events "$events_json" \
        --slurpfile works "$works_json" \
        --slurpfile videos "$videos_json" \
        '{
            "@context": "https://schema.org",
            "@graph": ($works[0] + $events[0] + $videos[0])
        }')

    talks_block=$(printf '    <script type="application/ld+json">\n%s\n    </script>' "$talks_jsonld")
    talks_block_file=$(mktemp)
    printf '%s\n' "$talks_block" > "$talks_block_file"

    awk -v bf="$talks_block_file" '
        /<!-- TALKS_JSONLD_START -->/ {
            print
            while ((getline line < bf) > 0) print line
            close(bf)
            skip = 1
            next
        }
        /<!-- TALKS_JSONLD_END -->/ {
            skip = 0
            print
            next
        }
        !skip { print }
    ' "$TALKS_INDEX_FILE" > "$TALKS_INDEX_FILE.new" && mv "$TALKS_INDEX_FILE.new" "$TALKS_INDEX_FILE"

    echo "Updated talks JSON-LD on $TALKS_INDEX_FILE"

    # === workPerformed JSON-LD on index.html ===

    wp_jsonld=$(jq -n \
        --arg pid "$PERSON_ID" \
        --slurpfile events "$events_json" \
        '{
            "@context": "https://schema.org",
            "@graph": [{
                "@type": "Person",
                "@id": $pid,
                "workPerformed": $events[0]
            }]
        }')

    wp_block=$(printf '    <script type="application/ld+json">\n%s\n    </script>' "$wp_jsonld")
    wp_block_file=$(mktemp)
    printf '%s\n' "$wp_block" > "$wp_block_file"

    awk -v bf="$wp_block_file" '
        /<!-- WORK_PERFORMED_JSONLD_START -->/ {
            print
            while ((getline line < bf) > 0) print line
            close(bf)
            skip = 1
            next
        }
        /<!-- WORK_PERFORMED_JSONLD_END -->/ {
            skip = 0
            print
            next
        }
        !skip { print }
    ' index.html > index.html.new && mv index.html.new index.html
    rm "$wp_block_file"
    echo "Updated workPerformed JSON-LD on index.html"

    rm "$events_json" "$works_json" "$videos_json" "$talks_block_file"

    # === hasCredential JSON-LD on index.html (from Credly) ===

    CREDLY_USER="${CREDLY_USER:-pfeifferj}"
    CREDLY_CACHE="data/credly-cache.json"
    credly_json=$(mktemp)
    if command -v curl &> /dev/null; then
        if curl -sSL --max-time 15 -A "Mozilla/5.0" \
            "https://www.credly.com/users/${CREDLY_USER}/badges.json?sort=most_popular" \
            -o "$credly_json" 2>/dev/null && jq -e '.data | length > 0' "$credly_json" > /dev/null 2>&1; then
            cp "$credly_json" "$CREDLY_CACHE"
            echo "Fetched Credly badges (cached to $CREDLY_CACHE)"
        elif [[ -f "$CREDLY_CACHE" ]]; then
            cp "$CREDLY_CACHE" "$credly_json"
            echo "Credly fetch failed, using cached $CREDLY_CACHE"
        fi
    elif [[ -f "$CREDLY_CACHE" ]]; then
        cp "$CREDLY_CACHE" "$credly_json"
        echo "curl not found, using cached $CREDLY_CACHE"
    fi

    if jq -e '.data | length > 0' "$credly_json" > /dev/null 2>&1; then
        echo "Generating hasCredential JSON-LD..."
        cred_jsonld=$(jq -n \
            --arg pid "$PERSON_ID" \
            --slurpfile credly "$credly_json" \
            '{
                "@context": "https://schema.org",
                "@graph": [{
                    "@type": "Person",
                    "@id": $pid,
                    "hasCredential": (
                        $credly[0].data
                        | map(select(.state == "accepted"))
                        | map(select(.badge_template.type_category == "Certification" or .badge_template.type_category == "Learning"))
                        | sort_by(.issued_at_date) | reverse
                        | map({
                            "@type": "EducationalOccupationalCredential",
                            "name": .badge_template.name,
                            "credentialCategory": "certification",
                            "dateCreated": (.issued_at_date | split("-")[0]),
                            "recognizedBy": {
                                "@type": "Organization",
                                "name": .badge_template.issuer.entities[0].entity.name
                            },
                            "url": ("https://www.credly.com/badges/" + .id)
                          })
                    )
                }]
            }')

        cred_block_file=$(mktemp)
        printf '    <script type="application/ld+json">\n%s\n    </script>\n' "$cred_jsonld" > "$cred_block_file"

        awk -v bf="$cred_block_file" '
            /<!-- HAS_CREDENTIAL_JSONLD_START -->/ {
                print
                while ((getline line < bf) > 0) print line
                close(bf)
                skip = 1
                next
            }
            /<!-- HAS_CREDENTIAL_JSONLD_END -->/ {
                skip = 0
                print
                next
            }
            !skip { print }
        ' index.html > index.html.new && mv index.html.new index.html
        rm "$cred_block_file"
        echo "Updated hasCredential JSON-LD on index.html"
    else
        echo "No Credly data available, skipping hasCredential generation"
    fi

    # === Visible #section-certs list (from same Credly data) ===

    if jq -e '.data | length > 0' "$credly_json" > /dev/null 2>&1; then
        certs_html_file=$(mktemp)
        jq -r '
            .data
            | map(select(.state == "accepted"))
            | map(select(.badge_template.type_category == "Certification" or .badge_template.type_category == "Learning"))
            | sort_by(.issued_at_date) | reverse
            | map("            <span class=\"cert-item\">" + (.badge_template.name | @html) + " (" + (.issued_at_date | split("-")[0]) + ")</span><br />")
            | .[]
        ' "$credly_json" > "$certs_html_file"

        awk -v bf="$certs_html_file" '
            /<!-- CERTS_LIST_START -->/ {
                print
                while ((getline line < bf) > 0) print line
                close(bf)
                skip = 1
                next
            }
            /<!-- CERTS_LIST_END -->/ {
                skip = 0
                print
                next
            }
            !skip { print }
        ' index.html > index.html.new && mv index.html.new index.html
        rm "$certs_html_file"
        echo "Updated #section-certs list on index.html"
    fi
    rm "$credly_json"

    # === memberOf JSON-LD on index.html (from data/memberships/) ===

    MEMBERSHIPS_DIR="data/memberships"
    if [[ -d "$MEMBERSHIPS_DIR" ]]; then
        echo "Generating memberOf JSON-LD..."
        memberships_arr=$(mktemp); echo "[]" > "$memberships_arr"
        volunteer_html_file=$(mktemp)
        for md in $(find "$MEMBERSHIPS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
            m_name=$(grep -m 1 "^name:" "$md" | sed 's/^name: *//')
            m_url=$(grep -m 1 "^url:" "$md" | sed 's/^url: *//')
            m_desc=$(grep -m 1 "^description:" "$md" | sed 's/^description: *//')
            jq --arg name "$m_name" --arg url "$m_url" --arg desc "$m_desc" \
                '. += [({
                    "@type": "Organization",
                    "name": $name,
                    "url": $url,
                    "description": $desc
                } | with_entries(select(.value != null and .value != "")))]' \
                "$memberships_arr" > "$memberships_arr.tmp" && mv "$memberships_arr.tmp" "$memberships_arr"

            esc_name=$(jq -rn --arg s "$m_name" '$s | @html')
            esc_desc=$(jq -rn --arg s "$m_desc" '$s | @html')
            if [[ -n "$esc_desc" ]]; then
                printf '            <span class="item">%s: %s</span><br />\n' "$esc_name" "$esc_desc" >> "$volunteer_html_file"
            else
                printf '            <span class="item">%s</span><br />\n' "$esc_name" >> "$volunteer_html_file"
            fi
        done

        awk -v bf="$volunteer_html_file" '
            /<!-- VOLUNTEER_LIST_START -->/ {
                print
                while ((getline line < bf) > 0) print line
                close(bf)
                skip = 1
                next
            }
            /<!-- VOLUNTEER_LIST_END -->/ {
                skip = 0
                print
                next
            }
            !skip { print }
        ' index.html > index.html.new && mv index.html.new index.html
        rm "$volunteer_html_file"
        echo "Updated #section-volunteer list on index.html"

        if [[ $(jq 'length' "$memberships_arr") -gt 0 ]]; then
            mem_jsonld=$(jq -n \
                --arg pid "$PERSON_ID" \
                --slurpfile orgs "$memberships_arr" \
                '{
                    "@context": "https://schema.org",
                    "@graph": [{
                        "@type": "Person",
                        "@id": $pid,
                        "memberOf": $orgs[0]
                    }]
                }')

            mem_block_file=$(mktemp)
            printf '    <script type="application/ld+json">\n%s\n    </script>\n' "$mem_jsonld" > "$mem_block_file"

            awk -v bf="$mem_block_file" '
                /<!-- MEMBER_OF_JSONLD_START -->/ {
                    print
                    while ((getline line < bf) > 0) print line
                    close(bf)
                    skip = 1
                    next
                }
                /<!-- MEMBER_OF_JSONLD_END -->/ {
                    skip = 0
                    print
                    next
                }
                !skip { print }
            ' index.html > index.html.new && mv index.html.new index.html
            rm "$mem_block_file"
            echo "Updated memberOf JSON-LD on index.html"
        fi
        rm "$memberships_arr"
    fi

    # === publishedMediaObject JSON-LD on index.html (from blog/*.md + data/publications/) ===

    PUBLICATIONS_DIR="data/publications"
    if [[ ${#sorted_files[@]} -gt 0 || -d "$PUBLICATIONS_DIR" ]]; then
        echo "Generating publishedMediaObject JSON-LD..."
        media_arr=$(mktemp); echo "[]" > "$media_arr"
        for file in "${sorted_files[@]}"; do
            post_data="${posts[$file]}"
            IFS='|' read -r p_title p_date p_desc _ _ _ p_external p_url p_publication <<< "$post_data"

            if [[ "$p_external" == "true" ]]; then
                p_link="$p_url"
            else
                p_link="${SITE_URL}/blog/$file"
            fi

            jq --arg name "$p_title" \
               --arg date "$p_date" \
               --arg desc "$p_desc" \
               --arg url "$p_link" \
               --arg publication "$p_publication" \
                '. += [({
                    "@type": "Article",
                    "headline": $name,
                    "url": $url,
                    "datePublished": $date,
                    "description": $desc,
                    "publisher": (if $publication != "" then {"@type": "Organization", "name": $publication} else null end)
                } | with_entries(select(.value != null and .value != "" and .value != {})))]' \
                "$media_arr" > "$media_arr.tmp" && mv "$media_arr.tmp" "$media_arr"
        done

        if [[ -d "$PUBLICATIONS_DIR" ]]; then
            for md in $(find "$PUBLICATIONS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
                pub_title=$(grep -m 1 "^title:" "$md" | sed 's/^title: *//')
                pub_url=$(grep -m 1 "^url:" "$md" | sed 's/^url: *//')
                pub_date=$(grep -m 1 "^datePublished:" "$md" | sed 's/^datePublished: *//')
                pub_publisher=$(grep -m 1 "^publisher:" "$md" | sed 's/^publisher: *//')
                pub_type=$(grep -m 1 "^type:" "$md" | sed 's/^type: *//')
                [[ -z "$pub_type" ]] && pub_type="Article"
                pub_desc=$(md_body "$md" | first_paragraph)

                jq --arg type "$pub_type" \
                   --arg name "$pub_title" \
                   --arg url "$pub_url" \
                   --arg date "$pub_date" \
                   --arg desc "$pub_desc" \
                   --arg publisher "$pub_publisher" \
                    '. += [({
                        "@type": $type,
                        "headline": $name,
                        "url": $url,
                        "datePublished": $date,
                        "description": $desc,
                        "publisher": (if $publisher != "" then {"@type": "Organization", "name": $publisher} else null end)
                    } | with_entries(select(.value != null and .value != "" and .value != {})))]' \
                    "$media_arr" > "$media_arr.tmp" && mv "$media_arr.tmp" "$media_arr"
            done
        fi

        if [[ $(jq 'length' "$media_arr") -gt 0 ]]; then
            media_jsonld=$(jq -n \
                --arg pid "$PERSON_ID" \
                --slurpfile articles "$media_arr" \
                '{
                    "@context": "https://schema.org",
                    "@graph": [{
                        "@type": "Person",
                        "@id": $pid,
                        "publishedMediaObject": $articles[0]
                    }]
                }')

            media_block_file=$(mktemp)
            printf '    <script type="application/ld+json">\n%s\n    </script>\n' "$media_jsonld" > "$media_block_file"

            awk -v bf="$media_block_file" '
                /<!-- PUBLISHED_MEDIA_JSONLD_START -->/ {
                    print
                    while ((getline line < bf) > 0) print line
                    close(bf)
                    skip = 1
                    next
                }
                /<!-- PUBLISHED_MEDIA_JSONLD_END -->/ {
                    skip = 0
                    print
                    next
                }
                !skip { print }
            ' index.html > index.html.new && mv index.html.new index.html
            rm "$media_block_file"
            echo "Updated publishedMediaObject JSON-LD on index.html"
        fi
        rm "$media_arr"
    fi

    # === llms.txt and llms-full.txt ===

    echo "Generating llms.txt and llms-full.txt..."

    {
        echo "# josie.lol"
        echo ""
        echo "> Personal website of Josephine Pfeiffer, Senior Software Engineer at Red Hat. Cloud-native infrastructure, Kubernetes, mainframes, security, developer productivity."
        echo ""
        echo "josie works on infrastructure and security. she spends work hours on things like confidential containers, free time on porting distros to weird architectures, and contributing to CNCF projects. she unironically thinks s390x is cool and will argue about it. occasionally writes crystal, and likes electronics with transparent cases."
        echo ""
        echo "## About"
        echo ""
        echo "- [Homepage](${SITE_URL}/): bio, certifications, sameAs links"
        echo ""
        echo "## Talks"
        echo ""
        for md_file in $(find "$TALKS_DIR" -name "*.md" | grep -v "index.md" | grep -v "template.md" | sort); do
            t_title=$(grep -m 1 "^title:" "$md_file" | sed 's/^title: *//')
            t_abstract=$(grep -m 1 "^abstract:" "$md_file" | sed 's/^abstract: *//')
            t_slug=$(basename "${md_file%.md}")
            short_abs=$(echo "$t_abstract" | head -c 200)
            echo "- [${t_title}](${SITE_URL}/talks/#talk-${t_slug}): ${short_abs}"
        done
        echo ""
        if [[ "$books_count" -gt 0 ]]; then
            echo "## Books"
            echo ""
            b_idx=0
            for md in $(find "$BOOKS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
                b_title=$(grep -m 1 "^title:" "$md" | sed 's/^title: *//')
                b_url=$(grep -m 1 "^url:" "$md" | sed 's/^url: *//')
                b_desc=$(md_body "$md" | first_paragraph)
                [[ -z "$b_url" ]] && b_url="${SITE_URL}/#book-${b_idx}"
                echo "- [${b_title}](${b_url}): ${b_desc}"
                b_idx=$((b_idx + 1))
            done
            echo ""
        fi
        if [[ "$papers_count" -gt 0 ]]; then
            echo "## Papers"
            echo ""
            p_idx=0
            for md in $(find "$PAPERS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
                p_title=$(grep -m 1 "^title:" "$md" | sed 's/^title: *//')
                p_url=$(grep -m 1 "^url:" "$md" | sed 's/^url: *//')
                p_abstract=$(md_body "$md" | first_paragraph)
                [[ -z "$p_url" ]] && p_url="${SITE_URL}/#paper-${p_idx}"
                echo "- [${p_title}](${p_url}): ${p_abstract}"
                p_idx=$((p_idx + 1))
            done
            echo ""
        fi
    } > llms.txt
    echo "Generated llms.txt"

    {
        echo "# josie.lol"
        echo ""
        echo "Personal website of Josephine Pfeiffer, Senior Software Engineer at Red Hat. Focus areas: cloud-native infrastructure, Kubernetes, mainframes (s390x, z/OS on OpenShift), container security, developer productivity, and Internal Developer Platforms."
        echo ""
        echo "josie works on infrastructure and security. she spends work hours on things like confidential containers, free time on porting distros to weird architectures, and contributing to CNCF projects. she unironically thinks s390x is cool and will argue about it. occasionally writes crystal, and likes electronics with transparent cases."
        echo ""
        echo "## Talks"
        echo ""
        for md_file in $(find "$TALKS_DIR" -name "*.md" | grep -v "index.md" | grep -v "template.md" | sort); do
            t_title=$(grep -m 1 "^title:" "$md_file" | sed 's/^title: *//')
            t_abstract=$(grep -m 1 "^abstract:" "$md_file" | sed 's/^abstract: *//')
            echo "### ${t_title}"
            echo ""
            echo "${t_abstract}"
            echo ""
            echo "Presented at:"
            sed -n '/^conferences:/,/^---/p' "$md_file" | grep -E "^\s+-\s+name:|^\s+location:|^\s+date:" | sed -E 's/^\s+/- /; s/\s+/ /g'
            echo ""
        done
        if [[ "$books_count" -gt 0 ]]; then
            echo "## Books"
            echo ""
            for md in $(find "$BOOKS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
                b_title=$(grep -m 1 "^title:" "$md" | sed 's/^title: *//')
                b_body=$(md_body "$md")
                echo "### ${b_title}"
                echo ""
                echo "$b_body"
                echo ""
            done
        fi
        if [[ "$papers_count" -gt 0 ]]; then
            echo "## Papers"
            echo ""
            for md in $(find "$PAPERS_DIR" -name "*.md" | grep -v "/template.md$" | sort); do
                p_title=$(grep -m 1 "^title:" "$md" | sed 's/^title: *//')
                p_body=$(md_body "$md")
                echo "### ${p_title}"
                echo ""
                echo "$p_body"
                echo ""
            done
        fi
    } > llms-full.txt
    echo "Generated llms-full.txt"
fi

# === .well-known/security.txt ===

SECURITY_DIR=".well-known"
SECURITY_FILE="$SECURITY_DIR/security.txt"

needs_regen=true
if [[ -f "$SECURITY_FILE" ]]; then
    current_expires=$(grep -m 1 "^Expires:" "$SECURITY_FILE" | sed 's/^Expires: *//')
    if [[ -n "$current_expires" ]]; then
        cutoff=$(date -u -d '+60 days' +%s 2>/dev/null || date -u -v+60d +%s 2>/dev/null || echo 0)
        current_ts=$(date -u -d "$current_expires" +%s 2>/dev/null || echo 0)
        if [[ "$current_ts" -gt "$cutoff" ]]; then
            needs_regen=false
        fi
    fi
fi

if [[ "$needs_regen" == true ]]; then
    expires=$(date -u -d '+11 months' +%Y-%m-%dT00:00:00Z 2>/dev/null || \
              date -u -v+11m +%Y-%m-%dT00:00:00Z 2>/dev/null || \
              echo "")
    if [[ -n "$expires" ]]; then
        mkdir -p "$SECURITY_DIR"
        cat > "$SECURITY_FILE" <<EOF
Contact: mailto:hi@josie.lol
Contact: https://go.josie.lol/signal
Expires: $expires
Preferred-Languages: en
Canonical: ${SITE_URL}/.well-known/security.txt
EOF
        echo "Regenerated $SECURITY_FILE (Expires: $expires)"
    else
        echo "Skipping security.txt: could not compute future date"
    fi
else
    echo "$SECURITY_FILE current (Expires: $current_expires)"
fi

echo "All build operations completed successfully!"
