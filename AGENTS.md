# AGENTS.md

This document outlines the standards and conventions for creating and maintaining this Quarto blog. Following these guidelines will ensure consistency, improve search engine optimization (SEO), and streamline the content creation process.

## Blog Post Structure

Each new blog post must be contained within its own subdirectory inside the `posts/` directory. The subdirectory name should be a shortened, URL-friendly version of the post's title (e.g., `using-r-with-quarto`).

Each post subdirectory must contain an `index.qmd` file, which will serve as the main content file for the post. Any images or other assets associated with the post should be placed in the same subdirectory.

## Metadata Standards

The following metadata fields are required in the YAML front matter of each `index.qmd` file:

-   `title`: The title of the blog post.
-   `author`: The name of the author.
-   `date`: The date the post was published, in `YYYY-MM-DD` format.
-   `description`: A brief, one-sentence summary of the post's content. This is crucial for SEO, as it will be used as the meta description for the page.
-   `categories`: A list of relevant categories for the post.

### Example

```yaml
---
title: "My New Blog Post"
author: "John Doe"
date: "2024-01-01"
description: "This is a brief summary of my new blog post."
categories:
  - R
  - Quarto
  - Data Science
---
```
