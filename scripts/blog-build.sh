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
TALKS_TEMPLATE_FILE="$TALKS_DIR/template.html"
TALKS_INDEX_FILE="$TALKS_DIR/index.html"

# Ensure required commands are available
if ! command -v pandoc &> /dev/null; then
    echo "Error: pandoc is not installed. Please install it with:"
    echo "  sudo pacman -S pandoc  # For Arch Linux"
    exit 1
fi

echo "🔄 Building blog posts from Markdown..."

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
    echo "📝 Created new RSS feed file"
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
    
    echo "🔨 Processing: $filename"
    
    # Extract metadata from markdown file
    title=$(grep -m 1 "^title:" "$md_file" | sed 's/^title: *//')
    date=$(grep -m 1 "^date:" "$md_file" | sed 's/^date: *//')
    author=$(grep -m 1 "^author:" "$md_file" | sed 's/^author: *//')
    description=$(grep -m 1 "^description:" "$md_file" | sed 's/^description: *//')
    tags_line=$(grep -m 1 "^tags:" "$md_file" | sed 's/^tags: *//')
    
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
        echo "🔗 External post detected, skipping HTML generation"
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
    
    # Read the tags HTML and content files
    tags_html=$(cat "$tags_html_file")
    
    # Create a temp file for the final HTML
    final_html=$(mktemp)
    
    # Generate guest post badge and bio HTML
    guest_badge_html=""
    guest_bio_html=""
    
    if [[ "$guest_post" == "true" ]]; then
        guest_badge_html='<span class="guest-post-badge">Guest Post</span>'
        
        if [[ ! -z "$guest_bio" ]]; then
            # Escape special characters in guest bio
            escaped_bio=$(printf '%s' "$guest_bio" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
            guest_bio_html="<div class=\"guest-author-bio\"><h3>About the Guest Author</h3><p>$escaped_bio</p>"
            if [[ ! -z "$guest_link" ]]; then
                guest_bio_html+="<p><a href=\"$guest_link\" target=\"_blank\" rel=\"noopener noreferrer\">Learn more about $author →</a></p>"
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
                # Regular line, just copy it
                echo "$line" >> "$final_html"
            fi
        fi
    done < "$working_file"
    
    # Copy the final HTML to the target location
    cp "$final_html" "$BLOG_DIR/$html_filename"
    
    # Clean up temp files
    rm "$tags_html_file" "$content_file" "$working_file" "$final_html"
    
    echo "✅ Generated: $BLOG_DIR/$html_filename"
    
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
IFS=$'\n' sorted_files=($(
    for file in "${post_files[@]}"; do
        date=$(echo "${posts[$file]}" | cut -d'|' -f2)
        echo "$date|$file"
    done | sort -r | cut -d'|' -f2
))
unset IFS

# Update blog index.html with post list
if [ -f "$INDEX_FILE" ]; then
    echo "🔄 Updating blog index..."
    
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
                    badges+=' <span class="guest-post-badge">Guest Post</span>'
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
    
    echo "✅ Updated blog index page"
fi

# Update RSS feed with posts
if [ -f "$RSS_FILE" ]; then
    echo "🔄 Updating RSS feed..."
    
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
                
                # Convert date to RFC822 format for RSS
                rfc_date=$(date -d "$date" -R 2>/dev/null || date -R)
                
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
            # Update the lastBuildDate
            echo "  <lastBuildDate>$(date -R)</lastBuildDate>" >> "$temp_rss"
        elif [[ "$in_posts" == false ]]; then
            echo "$line" >> "$temp_rss"
        fi
    done < "$RSS_FILE"
    
    # Replace the original RSS file
    cp "$temp_rss" "$RSS_FILE"
    rm "$temp_rss"
    
    echo "✅ Updated RSS feed"
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

echo "🎉 Blog build completed successfully!"

# After processing blog posts, process talks
echo "🔄 Building talks index..."

# Check if the index file exists and has the right markers
if ! grep -q "<!-- TALKS_LIST_START -->" "$TALKS_INDEX_FILE"; then
    echo "⚠️ Could not find TALKS_LIST_START marker in $TALKS_INDEX_FILE"
    exit 1
fi

if ! grep -q "<!-- TALKS_LIST_END -->" "$TALKS_INDEX_FILE"; then
    echo "⚠️ Could not find TALKS_LIST_END marker in $TALKS_INDEX_FILE"
    exit 1
fi

# Create a temp file for the rebuilt index
temp_index=$(mktemp)

# Copy everything before the TALKS_LIST_START marker
sed -n '1,/<!-- TALKS_LIST_START -->/p' "$TALKS_INDEX_FILE" > "$temp_index"

# Find markdown files
talk_files=$(find "$TALKS_DIR" -name "*.md" | grep -v "index.md" | grep -v "template.md")
talk_count=$(echo "$talk_files" | wc -l)
echo "📊 Found $talk_count talk markdown files"

# Array to store talk data for sorting
declare -a talk_data_array=()

# First pass: collect all talk data
for md_file in $talk_files; do
    filename=$(basename "$md_file")
    echo "🔨 Processing talk: $filename"
    
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
                    conf_entry+="<div class=\"text-sm text-gray-500 italic\">Cancelled</div>"
                else
                    conf_entry+="<div class=\"font-semibold\">$conf_name</div>"
                    conf_entry+="<div class=\"text-sm text-gray-500\">$conf_location ($conf_date)</div>"
                    
                    # Add upcoming badge if conference is in the future
                    if [[ "$is_upcoming" == "true" ]]; then
                        conf_entry+="<div class=\"text-sm\"><span class=\"inline-block px-2 py-1 bg-green-900 bg-opacity-30 text-green-400 rounded text-xs font-semibold\">UPCOMING</span></div>"
                    fi
                fi
                
                # Add links for this conference (only if not cancelled)
                if [[ "$conf_cancelled" != "true" && (! -z "$conf_slides" || ! -z "$conf_recording") ]]; then
                    conf_entry+="<div class=\"mt-1\">"
                    if [[ ! -z "$conf_slides" ]]; then
                        conf_entry+="<a href=\"$conf_slides\" class=\"text-purple-500 dark:text-purple-400 mr-3 text-sm no-underline transition-colors duration-200 hover:text-white hover:underline\">Slides</a>"
                    fi
                    if [[ ! -z "$conf_recording" ]]; then
                        conf_entry+="<a href=\"$conf_recording\" class=\"text-purple-500 dark:text-purple-400 text-sm no-underline transition-colors duration-200 hover:text-white hover:underline\">Recording</a>"
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
    
    echo "✅ Collected $title"
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
          <p class="mb-4"><a href="$related_post" class="text-purple-500 dark:text-purple-400 no-underline transition-colors duration-200 hover:text-white hover:underline">📝 Read related blog post →</a></p>
EOF
    fi
    
    cat >> "$temp_index" << EOF
          <div class="text-base text-gray-400">
            <p class="mb-2 font-bold">Presented at:</p>
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

echo "✅ Updated talks index page at $TALKS_INDEX_FILE"

# After processing blog posts and talks, generate sitemap
echo "🔄 Generating sitemap..."

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

echo "✅ Generated sitemap at $SITEMAP_FILE"

# Process pinned talks for the main page
echo "🔄 Processing pinned talks for main page..."

# Array to store pinned talk data for sorting
declare -a pinned_talk_data=()

# Find talks with pinned: true
for md_file in $talk_files; do
    if grep -q "^pinned: true" "$md_file"; then
        filename=$(basename "$md_file")
        title=$(grep -m 1 "^title:" "$md_file" | sed 's/^title: *//')
        date=$(grep -m 1 "^date:" "$md_file" | sed 's/^date: *//')
        
        # Extract first conference
        conf_line=$(grep -n "^conferences:" "$md_file" | cut -d: -f1)
        first_conf=""
        
        if [[ ! -z "$conf_line" ]]; then
            # Read through the conferences section to get the first one
            in_conferences=false
            conf_name=""
            conf_date=""
            
            while IFS= read -r line; do
                if [[ "$line" == "conferences:" ]]; then
                    in_conferences=true
                    continue
                fi
                
                if [[ "$in_conferences" == true ]]; then
                    if [[ "$line" == "---" || "$line" == "" ]]; then
                        break
                    fi
                    
                    if [[ "$line" =~ name: ]]; then
                        conf_name=$(echo "$line" | sed 's/.*name:[[:space:]]*//')
                    fi
                    
                    if [[ "$line" =~ date: ]]; then
                        conf_date=$(echo "$line" | sed 's/.*date:[[:space:]]*//')
                        first_conf="${conf_name} (${conf_date})"
                        break
                    fi
                fi
            done < "$md_file"
        fi
        
        # Store pinned talk data for sorting
        pinned_temp_file=$(mktemp)
        echo "$date|$title|$first_conf" > "$pinned_temp_file"
        pinned_talk_data+=("$pinned_temp_file")
    fi
done

# Sort pinned talks by date in descending order
if [ ${#pinned_talk_data[@]} -gt 0 ]; then
    sorted_pinned_talks=$(for file in "${pinned_talk_data[@]}"; do
        if [[ -f "$file" ]]; then
            echo "$(head -n1 "$file" | cut -d'|' -f1)|$file"
        fi
    done | sort -r | cut -d'|' -f2)
else
    sorted_pinned_talks=""
fi

# Build the pinned talks output
pinned_talks=""
talk_count=0
# Count the number of sorted pinned talks properly
if [[ ! -z "$sorted_pinned_talks" ]]; then
    total_pinned=$(echo "$sorted_pinned_talks" | wc -l)
else
    total_pinned=0
fi

echo "  Found $total_pinned pinned talks"

if [ $total_pinned -gt 0 ]; then
    for pinned_file in $sorted_pinned_talks; do
        echo "  Processing pinned file: $pinned_file"
        # Check if file exists
        if [[ ! -f "$pinned_file" ]]; then
            echo "  Warning: Pinned file does not exist: $pinned_file"
            continue
        fi
        # Read the entire line and parse it
        line=$(cat "$pinned_file" 2>/dev/null || echo "|||")
        date=$(echo "$line" | cut -d'|' -f1)
        title=$(echo "$line" | cut -d'|' -f2)
        first_conf=$(echo "$line" | cut -d'|' -f3)
        talk_count=$((talk_count + 1))
        
        if [ $talk_count -eq $total_pinned ]; then
            # Last entry uses └──
            pinned_talks="${pinned_talks}└── <span class=\"font-bold text-indigo-700 dark:text-purple-300\">${title}</span>
│   └── <span class=\"text-teal-700 dark:text-teal-300\">${first_conf}</span>
"
        else
            # Other entries use ├──
            pinned_talks="${pinned_talks}├── <span class=\"font-bold text-indigo-700 dark:text-purple-300\">${title}</span>
│   └── <span class=\"text-teal-700 dark:text-teal-300\">${first_conf}</span>
"
        fi
        
        # Clean up temp file
        rm -f "$pinned_file"
    done
fi

# Fix the last line indent
if [[ ! -z "$pinned_talks" ]]; then
    # Remove trailing newline
    pinned_talks=${pinned_talks%$'\n'}
    
    # Update the main index.html file with pinned talks
    main_index="index.html"
    if [ -f "$main_index" ]; then
        echo "🔄 Updating main page with pinned talks..."
        
        # Create a temp file
        temp_main=$(mktemp)
        
        # Read the main index and replace the talks section
        in_talks=false
        while IFS= read -r line; do
            if [[ "$line" == *"<pre class=\"font-mono whitespace-pre text-sm leading-tight pl-2 m-0 overflow-x-auto\"><span class=\"font-bold text-indigo-700 dark:text-purple-300\">/talks</span>"* ]]; then
                # Start of talks section - output the line and the new content
                echo "$line" >> "$temp_main"
                echo "$pinned_talks</pre>" >> "$temp_main"
                in_talks=true
            elif [[ "$in_talks" == true && "$line" == *"</pre>"* ]]; then
                # Skip the closing </pre> tag as we already added it
                in_talks=false
            elif [[ "$in_talks" == false ]]; then
                # Normal line, copy it
                echo "$line" >> "$temp_main"
            fi
        done < "$main_index"
        
        # Replace the original file
        cp "$temp_main" "$main_index"
        rm "$temp_main"
        
        echo "✅ Updated main page with pinned talks"
    fi
fi

echo "🎉 All build operations completed successfully!" 