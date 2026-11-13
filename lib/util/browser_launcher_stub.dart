/// Opens a url in a new browser tab.
///
/// On the web this has to happen **directly inside the tap handler**:
/// a browser only allows `window.open` while the user gesture is still
/// active. As soon as the call is delayed (for example by an `await` of
/// `canLaunchUrl`) the popup blocker silently drops it.
///
/// On every other platform the function does nothing, the app uses
/// `url_launcher` there.
bool openInNewTab(String url) => false;
