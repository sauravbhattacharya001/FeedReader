# FeedReader
An RSS Feed Reader for most read Reuters feeds.

### To run the app:

1. Start the project in Xcode by double clicking FeedReader.xcodeproj. 
2. Run the app on iPhone 5S simulator.

### To run unit tests:

1. Start the project in Xcode by double clicking FeedReader.xcodeproj. 
2. Go to test navigator and run the included tests in the app.

### Test cases:

1. Test with internet connection and without internet connection. Check whether data loads correctly when internet connection is lost at different times:
    1. Right at the beginning -> Should show a friendly message that connection needs to be online.
    2. While using the app -> Uses cached data
    3. On app restart -> Gets live data if connection available, else gets cached data.
3.  Check the title and description on the app are same between the cell view and detailed view (on tapping the cell).
4. Check that story link opens in browser on clicking the story link.

Tested only on iPhone.
