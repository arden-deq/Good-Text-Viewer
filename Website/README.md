# Good Text Viewer website

The site runs on the existing OCI Nginx server for [goodtextviewer.allmightdev.com](https://goodtextviewer.allmightdev.com). A Python 3 build renders English and Korean HTML from public GitHub Releases. Download links go directly to the assets on GitHub.

## Local preview

```sh
python3 Website/build.py .build/website
python3 -m http.server 8100 --directory .build/website
```

Visit http://localhost:8100 and open Downloads to check the release archive. The builder needs access to the public GitHub API. It includes stable version tags and prefers the macOS universal DMG and Windows x64 portable EXE, with ZIP links for older releases. Each platform gets its latest published build and the archive lists the files actually attached to each version.

## OCI

Nginx serves `/var/www/goodtextviewer/site/current`. Keep the site's Python source, templates, and assets in `/opt/goodtextviewer-site`. Install the Nginx and systemd files from `deploy/`. Create the `site` directory owned by `www-data`, then run the following as that user after updating the source.

```sh
python3 /opt/goodtextviewer-site/build.py --publish /var/www/goodtextviewer/site
```

The `goodtextviewer-site.timer` systemd unit runs this command every 15 minutes. Each successful run switches the `current` symlink to a complete build and retains the previous build for rollback. If the release API or build fails, Nginx continues serving the current files. The timer uses the public API without credentials. Each build also retrieves the repository’s star count. If that request fails, the GitHub link still appears without a count.

The hostname has its own Nginx virtual host and Let's Encrypt certificate. Its HTTP server leaves `/.well-known/acme-challenge/` available for automatic renewals through the Cloudflare proxied DNS record.

## GitHub star button

The static build links to GitHub by default. For inline starring, configure a GitHub App with the Good Text Viewer site as its homepage, `<site>/star/callback` as its callback URL, Starring (write) account permission, Metadata (read) repository permission, and webhooks disabled. Visitors authorize the app in GitHub and only clicking the site's star button can initiate a star for this repository.

Install `deploy/goodtextviewer-star.service` in `/etc/systemd/system/`. Store its `GTV_GITHUB_CLIENT_ID` and `GTV_GITHUB_CLIENT_SECRET` environment settings in `/etc/goodtextviewer/star.env`, readable only by root. The Node.js 18 service listens on loopback. It uses each visitor token for the requested action and does not store it. The service returns to the same site page and displays the GitHub result and latest available count.

After starting the star service and applying `deploy/nginx.conf`, install `deploy/goodtextviewer-site.service.d/github-star.conf` in `/etc/systemd/system/goodtextviewer-site.service.d/`. Reload systemd and run `goodtextviewer-site.service` to generate the form. Removing that drop-in and regenerating the site restores the GitHub link.
