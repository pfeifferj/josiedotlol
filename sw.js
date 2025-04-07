// Cache name with version
const CACHE_NAME = 'josie-lol-v33';
const OFFLINE_PAGE = '/offline.html';

// Files to cache
const urlsToCache = [
  '/',
  '/index.html',
  '/offline.html',
  '/favicon.ico',
  '/apple-touch-icon.png',
  '/favicon-16x16.png',
  '/favicon-32x32.png',
  '/safari-pinned-tab.svg',
  '/site.webmanifest',
  '/android-chrome-96x96.png',
  '/mstile-150x150.png',
  '/styles.css',
  'https://cdn.tailwindcss.com?v=3.3.3',
  'https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;700&display=swap',
  '/rss.xml'
];

// Install event - cache assets
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => {
        console.log('Cache opened');
        return cache.addAll(urlsToCache);
      })
      .then(() => self.skipWaiting())
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', event => {
  console.log('Service worker activated');
  
  // Clear all caches to force fresh reload
  event.waitUntil(
    caches.keys().then(cacheNames => {
      return Promise.all(
        cacheNames.map(cacheName => {
          console.log('Deleting cache:', cacheName);
          return caches.delete(cacheName);
        })
      );
    })
    .then(() => {
      console.log('All caches cleared, opening new cache:', CACHE_NAME);
      return caches.open(CACHE_NAME).then(cache => {
        return cache.addAll(urlsToCache);
      });
    })
    .then(() => self.clients.claim())
  );
});

// Fetch event - serve from cache or network
self.addEventListener('fetch', event => {
  // Skip for non-GET requests or browser-extension requests
  if (event.request.method !== 'GET' || event.request.url.startsWith('chrome-extension://')) {
    return;
  }
  
  event.respondWith(
    caches.match(event.request)
      .then(response => {
        // Cache hit - return the response from cache
        if (response) {
          return response;
        }

        // Clone the request
        const fetchRequest = event.request.clone();

        // Make network request and cache the response
        return fetch(fetchRequest)
          .then(response => {
            // Check if valid response
            if (!response || response.status !== 200 || response.type !== 'basic') {
              return response;
            }

            // Clone the response
            const responseToCache = response.clone();

            // Add to cache
            caches.open(CACHE_NAME)
              .then(cache => {
                cache.put(event.request, responseToCache);
              });

            return response;
          })
          .catch(() => {
            // If network fails and it's a navigation request (HTML page),
            // serve the offline page
            if (event.request.mode === 'navigate') {
              return caches.match(OFFLINE_PAGE);
            }
          });
      })
  );
}); 