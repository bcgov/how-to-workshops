# Image Registry

Here is a bash script you can run to determine how much space in the Image Registry your namespace is using. It will list all the Images, Tags, and Revisions in the namespace and sum their sizes in a human readable form.

This tool does not take into account that some image layers might be reused between tags/revisions and so may report a larger size than is actually stored on-disk in the registry. It is more intended to help understand what is contributing most to image registry usage.

## Prerequisites

The script uses `oc`, `jq` and `numfmt` to do all its work. As long as those are installed and in the path it should work. Of course, you also need to be logged in and have read access to the image streams in your namespce.

## What are Revisions?

When you push to a tag, a new revision is created with a new SHA. If you do a lot of builds in a short time, you might end up with a lot of revisions. There is a daily pruner job that runs that will keep only the most recent 3 revisions or any revisions created in the last 4 days.

## What should I do if I have a large usage?

If you are using separate tags for each build, be sure your CI process cleans up old tags. Having 200+ tags in an ImageStream is wasteful.

If you are doing lots of builds in a short time, push them to separate tags instead of just adding lots of revisions to latest. This way when you delete your tag the pruner can clean it up sooner.
