# Author: Madhusudan Kharote - SWE645 Homework 2
# Purpose: Builds a lightweight Nginx image that serves the HW1 Part 2 static site
# (homepage, student survey form, and error page) on port 80.

FROM nginx:1.27-alpine

# Replace the default Nginx site config with ours (adds the custom 404 page + health check)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy the website files (index.html, survey.html, error.html, profile.jpg)
COPY web/ /usr/share/nginx/html/

EXPOSE 80

# Run Nginx in the foreground so the container stays alive
CMD ["nginx", "-g", "daemon off;"]
