import React from "react";
import {markupTextInRange} from "../Helpers/range_selector";

export class NotebookViewer extends React.Component {
  constructor(props) {
    super(props);
    this.iframe = React.createRef();
  }

  componentDidMount() {
    if (this.props.resultView) {
      this.readyAnnotations();
    }
  }

  readyAnnotations = () => {
    annotation_type = ANNOTATION_TYPES.NOTEBOOK;
  };

  renderAnnotations = () => {
    const doc = this.iframe.current.contentWindow.document;
    // annotations need to be sorted in the order that they were created so that multiple
    // annotations on the same node get rendered in the order they were created. If they are
    // not, then the ranges may contain nodes/offsets that don't take the other highlighted
    // regions into account.
    this.props.annotations
      .sort((a, b) => (a.number > b.number ? 1 : -1))
      .forEach(annotation => {
        const start_node = doc.evaluate(annotation.start_node, doc).iterateNext();
        const end_node = doc.evaluate(annotation.end_node, doc).iterateNext();
        const newRange = doc.createRange();
        try {
          newRange.setStart(start_node, annotation.start_offset);
          newRange.setEnd(end_node, annotation.end_offset);
          markupTextInRange(newRange, annotation.content);
        } catch (error) {
          console.error(error);
        }
      });
  };

  componentDidUpdate(prevProps) {
    if (prevProps.annotations !== this.props.annotations) {
      this.renderAnnotations();
    }
  }

  render() {
    return (
      <div>
        <iframe
          className={"notebook"}
          id={"notebook"}
          key={this.props.url}
          onLoad={this.renderAnnotations}
          src={this.props.url + "&preview=true"}
          ref={this.iframe}
        />
      </div>
    );
  }
}
