/**
 * Booyaka Client App
 * 
 * This module initializes the client-side application, sets up UI interactions,
 * and provides utility functions for features like sticky sidebars and "time ago" formatting.
 */
const defaultAppOpts = {
  /**
   * Enable sticky sidebars that remain visible below the navbar when scrolling.
   * This is useful for keeping navigation or other important elements accessible.
   */
  enableStickySidebar: true,

  /**
   * Enable "time ago" formatting for <time> elements with a datetime attribute.
   * This converts timestamps into a human-readable format like "5 minutes ago".
   * It enhances the user experience by providing relative time information.
  */
  enableTimeAgo: true,

  /**
   * Enable animated alerts that follow the mouse cursor within the alert box.
   * This adds a dynamic visual effect to alert messages, making them more engaging.
   * The animation allows the alert to move slightly in response to mouse movements,
   * creating an interactive experience for the user.
  */
  enableAnimatedAlerts: true
}

export default {
  /**
   * Initialize the application with the given options.
   * This function sets up the UI features based on the provided options.
   * It also adds necessary event listeners and applies styles to checkboxes.
   * 
   * @param {Object} opts - Configuration options for initializing the app.
   * @param {boolean} opts.enableStickySidebar - Whether to enable sticky sidebars.
   * @param {boolean} opts.enableTimeAgo - Whether to enable "time ago" formatting.
   * @param {callback} opts.fetchAndSwapCallback - Optional callback to override the default fetchAndSwap behavior.
   *
  */
  init: function(opts = defaultAppOpts) {
    console.log("Booyaka Initialized");
    if (opts.enableStickySidebar) this.initStickySidebar();
    if (opts.enableTimeAgo) this.initTimeAgo();
    if (opts.enableAnimatedAlerts) this.initAnimatedAlerts();
    this.initSmoothAnchors();
    this.initExternalLinksDecorator();
    this.initSpotlightSearch();

    const fetchSwapCallback = function() {
      opts.enableAnimatedAlerts && this.initAnimatedAlerts();
      opts.fetchAndSwapCallback && opts.fetchAndSwapCallback();
    }.bind(this) // bind 'this' to ensure the correct context inside the callback

    // Intercept clicks on internal links to enable SPA-like navigation without full page reloads.
    let sidebarNavigation = document.querySelector('.sidebar-navigation')
    document.addEventListener('click', (e) => {
      const a = e.target.closest('a');
      if (a &&  a.href &&  a.origin === location.origin && !a.hasAttribute('download') && 
        !a.target &&  !a.href.startsWith('mailto:') &&  !a.href.startsWith('tel:') && !a.getAttribute('href').startsWith('#')) {
        e.preventDefault();
        // checking if the clicked element is part of the navigaiton menu
        // if so, we want to make the clicked item active and remove active from others
        if (sidebarNavigation && sidebarNavigation.contains(a)) {
          sidebarNavigation.querySelectorAll('a').forEach(link => link.classList.remove('active', 'bg-dark'));
          a.classList.add('active', 'bg-dark');
        }
        this.fetchAndSwap(a.pathname + a.search, true, fetchSwapCallback);
      }
    });

    document.querySelectorAll('input[type="checkbox"]').forEach(checkbox => {
      checkbox.classList.add('form-check-input'); // the bootstrap class
    });
  },

  initSpotlightSearch: function() {
    fetch("/results.json").then(response => response.json()).then(data => {
      if(!data) return;
      let spotlightForm = document.querySelector('.spotlight-form');
      let spotlightAutocomplete = document.createElement('div');
      spotlightAutocomplete.classList.add('position-fixed', 'border', 'border-dark', 'list-unstyled', 'w-100', 'rounded-4', 'p-2', 'd-none', 'spotlight-autocomplete');
      spotlightAutocomplete.style.top = '68px'
      spotlightAutocomplete.style.zIndex = '1050';
      spotlightAutocomplete.style.maxWidth = spotlightForm.offsetWidth + 'px';
      spotlightAutocomplete.style.left = spotlightForm.getBoundingClientRect().left + 'px';
      spotlightAutocomplete.style.backgroundColor = 'rgba(10,14,14,0.60)';
      spotlightAutocomplete.style.boxShadow = '0 30px 30px rgba(0,0,0,.8)';
      spotlightAutocomplete.style.backdropFilter = 'blur(34px)';
      
      spotlightAutocomplete.style.maxHeight = '280px';

      let spotlightInner = document.createElement('ul');
      spotlightInner.classList.add('m-0', 'p-0', 'spotlight-autocomplete-list');
      spotlightInner.style.overflowX = 'scroll';
      spotlightInner.style.maxHeight = '260px';
      
      spotlightAutocomplete.appendChild(spotlightInner);
      document.body.insertAdjacentElement('beforeend', spotlightAutocomplete);

      // Create Fuse instance
      let fuse = new Fuse(data.results, {
        keys: ['title', 'description', 'headings'],
        minMatchCharLength: 4, // Only match longer substrings
        includeMatches: true,
        threshold: 0.1, // Stricter matching
        distance: 500,
        useExtendedSearch: true, // Enable extended search
        findAllMatches: false,   // Only best matches
      });

      // clicking outside the autocomplete closes it
      document.addEventListener('click', function(event) {
        if (!spotlightForm.contains(event.target)) {
          spotlightAutocomplete.classList.add('d-none');
        }
      });
      
      // pressing cmd/ctrl + / focuses the search input
      var isSpotlightFocused = false;
      spotlightForm.querySelector('.spotlight').addEventListener('click', function() {
        isSpotlightFocused = true;
      });

      document.addEventListener('keydown', function(event) {
        if (event.key === '/' && (event.metaKey || event.ctrlKey)) {
          event.preventDefault();
          spotlightForm.querySelector('.spotlight').focus();
          isSpotlightFocused = true;
        }
        // handle arrow keys and enter for navigating the autocomplete list
        if (isSpotlightFocused) {
          let items = spotlightAutocomplete.querySelectorAll('.spotlight-autocomplete-item');
          var index = Array.from(items).findIndex(item => item.classList.contains('active'));
          if (event.key === 'ArrowDown') {
            event.preventDefault();
            if (index < items.length - 1) {
              if (index >= 0) items[index].classList.remove('active');
              items[++index].classList.add('active');
              items[index].scrollIntoView({ block: 'nearest' });
            }
          } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            if (index > 0) {
              items[index].classList.remove('active');
              items[--index].classList.add('active');
              items[index].scrollIntoView({ block: 'nearest' });
            }
          } else if (event.key === 'Enter') {
            event.preventDefault();
            if (index >= 0) {
              // before navigating, we want to collect the page title
              // and fill the search input with it, so that when user goes back,
              // they see the title of the page they visited instead of the search query
              let title = items[index].querySelector('span.d-block').textContent;
              spotlightForm.querySelector('.spotlight').value = title;
              // navigate to the selected page
              items[index].click();
            }
          }
        }
      });

      // Example search function
      function searchDocs(query) {
        const results = fuse.search(query);
        // results is an array of objects: { item, refIndex, ... }
        spotlightInner.innerHTML = '';
        if(results.length === 0) {
          spotlightAutocomplete.classList.add('d-none');
          return;
        }
        spotlightAutocomplete.classList.remove('d-none');
        for (let r of results) {
          let li = document.createElement('li');
          let a = document.createElement('a');
          a.classList.add('d-block', 'rounded-4', 'py-2', 'px-3', 'border-0', 'text-decoration-none', 'spotlight-autocomplete-item');
          a.href = r.item.url != '/' ? `/${r.item.url}` : '/';
          a.innerHTML = `<span class="d-block">${r.item.title}</span><span class="text-muted small d-block lh-sm">${r.item.description}</span>`;
          li.appendChild(a);

          // use provided indices to highlight matched terms
          for (let match of r.matches) {
            if (match.key === 'title' || match.key === 'description') {
              // Find the corresponding span for title/description
              let spanSelector = match.key === 'title' ? 'span.d-block' : 'span.text-muted';
              let span = a.querySelector(spanSelector);
              if (span) {
                let text = span.textContent;
                let highlighted = '';
                let lastIndex = 0;
                for (let range of match.indices) {
                  let start = range[0];
                  let end = range[1] + 1;
                  highlighted += text.slice(lastIndex, start);
                  highlighted += '<mark>' + text.slice(start, end) + '</mark>';
                  lastIndex = end;
                }
                highlighted += text.slice(lastIndex);
                span.innerHTML = highlighted;
              }
            }
          }
          spotlightInner.appendChild(li);
        }
      }
  
      let spotlight = document.querySelector('.spotlight');

      spotlight.addEventListener('keydown', function(event) {
        if (event.key === '/' && (event.metaKey || event.ctrlKey)) {
          event.preventDefault();
          spotlight.focus();
        } else if(event.key === 'Escape') {
          spotlightAutocomplete.classList.add('d-none');
        }
      });
  
      spotlight.addEventListener('input', function(event) {
        const query = event.target.value;
        if(query.length <= 3) {
          spotlightAutocomplete.classList.add('d-none');
          return;
        }
        searchDocs(query);
      });
    });
  },
  
  /**
   * Make sidebars sticky so they remain visible when scrolling down the page.
   */
  initStickySidebar: function() {
    const sidebars = document.querySelectorAll('.sticky-sidebar');
    const navbarHeight = document.querySelector('.navbar-container-area').offsetHeight;
    const extraPadding = 30; // px, adjust for pt-5 effect

    function updateSidebarTop() {
      for (const sidebar of sidebars) {
        const scrollY = window.scrollY || window.pageYOffset;
        sidebar.style.top = (navbarHeight + extraPadding) + 'px';
      }
    }
    window.addEventListener('scroll', updateSidebarTop);
    window.addEventListener('resize', updateSidebarTop);
    updateSidebarTop()
  },

  /**
   * Initialize smooth scrolling for internal anchor links.
   * This function ensures that when users click on links that point to anchors within the page,
   * the page will scroll smoothly to the target section, accounting for the height of the sticky navbar.
   */
  initSmoothAnchors: function() {
    // Smooth scroll to anchor, offset by sticky navbar height
    function scrollToAnchorWithOffset(hash) {
      const navbar = document.querySelector('.navbar-container-area');
      const navbarHeight = navbar ? navbar.offsetHeight : 0;
      const target = document.getElementById(hash);
      console.log(target)
      if (target) {
        const targetPosition = target.getBoundingClientRect().top + window.pageYOffset;
        window.scrollTo({
          top: targetPosition - navbarHeight,
          behavior: 'smooth'
        });
      }
    }

    // Attach click event to all internal anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
      anchor.addEventListener('click', function(e) {
        const rawHash = this.getAttribute('href');
        const hash = decodeURIComponent(rawHash.slice(1));
        if (hash) {
          const target = document.getElementById(hash) || document.querySelector(`[name="${hash}"]`);
          if (target) {
            e.preventDefault();
            scrollToAnchorWithOffset(hash);
            history.replaceState(null, null, rawHash);
          }
        }
      });
    });

    // If page loads with a hash, scroll to it with offset
    if (window.location.hash) {
      setTimeout(() => {
        const hash = window.location.hash.slice(1);
        scrollToAnchorWithOffset(hash);
      }, 100);
    }
  },


  /**
   * Fetches the given URL and swaps the content of the current
   * view with the new view from the response.
   * 
   * If the fetch fails or the expected view container is not
   * found in the response, it falls back to a full page reload.
   * 
   * @param {string} url - The URL to fetch and swap.
   * @param {boolean} pushState - Whether to push the new URL to the browser history (default: true).
   * @param {callback} callback - Optional callback to execute after successful content swap.
   * @returns {void}
  */
  fetchAndSwap(url, pushState = true, callback) {
    fetch(url, {headers: {'X-Requested-With': 'spa'}})
      .then(resp => {
        if (!resp.ok) throw new Error('Network error');
        return resp.text();
      })
      .then(html => {
        // parse the returned HTML and extract the new view
        const parser = new DOMParser();
        const doc = parser.parseFromString(html, 'text/html');
        const newView = doc.querySelector('[data-view]');
        const currentView = document.querySelector('[data-view]');
        const newToc = doc.querySelector('[data-view-right]');
        const currentToc = document.querySelector('[data-view-right]');
        let swapped = false;
        if (newView && currentView) {
          currentView.innerHTML = newView.innerHTML;
          swapped = true;
        }
        if (newToc && currentToc) {
          currentToc.innerHTML = newToc.innerHTML;
          swapped = true;
        }
        if (swapped) {
          if (pushState) history.pushState(null, '', url);
          window.scrollTo(0, 0);
          callback && callback(url, newView, newToc);
        } else {
          console.warn('Could not find view containers in the fetched HTML. Reloading the page as fallback.');
          location.href = url;
        }
      }).catch(() => location.href = url);
  },

  initExternalLinksDecorator: function() {
    // Function to check if a link is external
    function isExternalLink(anchor) {
      return anchor.hostname && anchor.hostname !== window.location.hostname;
    }

    // Example: Add 'external' class to all external links
    document.querySelectorAll('a[href]').forEach(a => {
      if (isExternalLink(a)) {
        a.classList.add('external');
        a.setAttribute('target', '_blank');
      }
    });
  },

  /**
   * Initialize the application with the default options.
   */
  initAnimatedAlerts: function() {
    document.querySelectorAll('.alert').forEach(alert => {
      const anim = document.createElement('div');
      anim.className = 'alert-animation';
      anim.style.left = '0px';
      anim.style.top = '0px';
      alert.style.position = 'relative';
      alert.insertAdjacentElement('afterbegin', anim);

      // Set your desired offset here
      const offsetX = 400; // pixels allowed to exceed horizontally
      const offsetY = 400; // pixels allowed to exceed vertically

      document.body.addEventListener('mousemove', e => {
        const rect = alert.getBoundingClientRect();
        const animW = anim.offsetWidth;
        const animH = anim.offsetHeight;
        let x = e.clientX - rect.left - animW / 2;
        let y = e.clientY - rect.top - animH / 2;

        // Allow exceeding by offset
        x = Math.max(-offsetX, Math.min(x, rect.width - animW + offsetX));
        y = Math.max(-offsetY, Math.min(y, rect.height - animH + offsetY));

        // Calculate rotation based on mouse position (example: angle from center)
        const centerX = rect.width / 2;
        const centerY = rect.height / 2;
        const dx = x + animW / 2 - centerX;
        const dy = y + animH / 2 - centerY;
        const angle = Math.atan2(dy, dx) * (18 / Math.PI); // degrees
        anim.style.transform = 'translate(' + x + 'px, ' + y + 'px) rotate(' + angle + 'deg)';
      });
    });
  },
  
  /**
   * Initialize "time ago" formatting for <time> elements.
   * 
   * Convert a date string into a "time ago" format.
   * Example: "2023-10-01 12:00:00" -> "5 minutes ago"
   */
  initTimeAgo: function() {
    function timeago(dateString) {
      const timeStrings = {
        minute: ["minute", "minutes"],
        hour: ["hour", "hours"],
        day: ["day", "days"],
      };
      
      function pluralize(unit, value) {
        return value === 1 ? timeStrings[unit][0] : timeStrings[unit][1];
      }
      const date = new Date(dateString.replace(' ', 'T'));
      const now = new Date();
      const diffMs = now - date;
      const diffSec = Math.floor(diffMs / 1000);
      const diffMin = Math.floor(diffSec / 60);
      const diffHour = Math.floor(diffMin / 60);
      const diffDay = Math.floor(diffHour / 24);

      if (diffSec < 60) return "just now";
      if (diffMin < 60) return diffMin + " " + pluralize("minute", diffMin) + " ago";
      if (diffHour < 24) return diffHour + " " + pluralize("hour", diffHour) + " ago";
      return diffDay + " " + pluralize("day", diffDay) + " ago";
    }
    document.querySelectorAll('time[datetime]').forEach(span => {
      span.textContent = timeago(span.getAttribute('datetime'));
    });
  }
}

document.addEventListener('DOMContentLoaded', () => {
  UI.init({
    enableStickySidebar: true,
    enableTimeAgo: true,
    enableAnimatedAlerts: true,
    fetchAndSwapCallback: (url, html) => {
      hljs.highlightAll();
    }
  });

  // Initial syntax highlighting for code blocks
  hljs.highlightAll();

  const toggleAreaBtns = document.querySelectorAll('button[data-toggle-area]');
  const mainArea = document.querySelector('div[data-area="main"]');
  const leftSidebar = document.querySelector('div[data-area="left"]');
  const rightSidebar = document.querySelector('div[data-area="right"]');

  // Load preferences from localStorage
  let isLeftSidebarVisible = localStorage.getItem('leftSidebarVisible') !== 'false';
  let isRightSidebarVisible = localStorage.getItem('rightSidebarVisible') !== 'false';

  function updateMainAreaCols() {
    if (!isLeftSidebarVisible && !isRightSidebarVisible) {
      mainArea.classList.remove('col-lg-7', 'col-lg-9');
      mainArea.classList.add('col-lg-12');
    } else if (!isLeftSidebarVisible || !isRightSidebarVisible) {
      mainArea.classList.remove('col-lg-7', 'col-lg-12');
      mainArea.classList.add('col-lg-9');
    } else {
      mainArea.classList.remove('col-lg-9', 'col-lg-12');
      mainArea.classList.add('col-lg-7');
    }
  }

  function updateSidebarVisibility() {
    if (isLeftSidebarVisible) {
      leftSidebar.classList.remove('d-none');
      leftSidebar.classList.add('d-lg-block');
    } else {
      leftSidebar.classList.remove('d-lg-block');
      leftSidebar.classList.add('d-none');
    }
    if (isRightSidebarVisible) {
      rightSidebar.classList.remove('d-none');
      rightSidebar.classList.add('d-lg-block');
    } else {
      rightSidebar.classList.remove('d-lg-block');
      rightSidebar.classList.add('d-none');
    }
  }

  toggleAreaBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const areaName = btn.getAttribute('data-toggle-area');
      const areaElement = document.querySelector(`div[data-area="${areaName}"]`);
      const icon = btn.querySelectorAll('span');
      if (areaElement.classList.contains('d-lg-block')) {
        areaElement.classList.remove('d-lg-block');
        areaElement.classList.add('d-none');
        if (areaName === 'left') {
          isLeftSidebarVisible = false;
          localStorage.setItem('leftSidebarVisible', 'false');
        } else if (areaName === 'right') {
          isRightSidebarVisible = false;
          localStorage.setItem('rightSidebarVisible', 'false');
        }
      } else {
        areaElement.classList.remove('d-none');
        areaElement.classList.add('d-lg-block');
        if (areaName === 'left') {
          isLeftSidebarVisible = true;
          localStorage.setItem('leftSidebarVisible', 'true');
        } else if (areaName === 'right') {
          isRightSidebarVisible = true;
          localStorage.setItem('rightSidebarVisible', 'true');
        }
      }
      updateMainAreaCols();
      // Optionally toggle icons here
      icon[0].classList.toggle('d-none');
      icon[1].classList.toggle('d-none');
    });
  });

  // Initial setup
  updateSidebarVisibility();
  updateMainAreaCols();
});